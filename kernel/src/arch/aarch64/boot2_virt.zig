// aarch64 boot stage 2: higher-half entry/exit glue (MMU on, virtual VAs).
// Ported from the old kernel_entry.S.
//
// boot1_phys.zig branches to `enter_virtual_addressing` once the MMU is on, so
// this code runs in the higher half.

extern fn kmain() callconv(.c) noreturn;

// Linker-script symbols (see linker.ld). 16-byte aligned; only their addresses
// are used.
extern var __bss_start: u8;
extern var __bss_end: u8;

const std = @import("std");
const kprint = @import("../../kprint.zig");
const DeviceTree = @import("DeviceTree");

/// Print the full path of every node in the device tree, root first then all
/// descendants in tree order (nodeIterator walks root's children, so root `/`
/// is printed separately).
fn dumpFdtNodes(dt: DeviceTree) !void {
    var buf: [256]u8 = undefined;

    kprint.write("  {s}\r", .{try DeviceTree.Node.root.path(dt, &buf)});

    var iter = try dt.nodeIterator(.root, .all_children, .any);
    while (try iter.next(dt)) |n| {
        kprint.write("  {s}\r", .{try n.node.path(dt, &buf)});
    }
}

/// Print the properties of every `memory` node. Per the devicetree spec memory
/// nodes are named `memory[@unit]` and live directly under the root, so `reg`
/// cells come from the root's #address-cells / #size-cells.
fn dumpMemoryNodes(dt: DeviceTree) !void {
    // Spec defaults when the property is absent: 2 address cells, 1 size cell.
    const addr_cells = (try DeviceTree.Node.root.addressCells(dt)) orelse 2;
    const size_cells = (try DeviceTree.Node.root.sizeCells(dt)) orelse 1;

    var node_iter = try dt.nodeIterator(.root, .all_children, .{ .name = "memory" });
    while (try node_iter.next(dt)) |n| {
        kprint.write("  {s}:\r", .{n.name});

        var prop_iter = try n.node.propertyIterator(dt, .any);
        while (try prop_iter.next()) |prop| {
            try printProperty(prop, addr_cells, size_cells);
        }
    }
}

/// Render one property as `name = value`. `reg` is decoded into <address size>
/// pairs; printable values are shown as strings; anything else as raw hex bytes.
fn printProperty(prop: DeviceTree.Property, addr_cells: u32, size_cells: u32) !void {
    if (std.mem.eql(u8, prop.name, "reg")) {
        kprint.write("    {s} =", .{prop.name});
        var reg = try prop.value.regIterator(addr_cells, size_cells);
        while (reg.next()) |r| kprint.write(" <0x{x} 0x{x}>", .{ r.address, r.size });
        kprint.write("\r", .{});
    } else if (looksLikeString(prop.value._raw)) {
        kprint.write("    {s} = \"{s}\"\r", .{ prop.name, prop.value.toString() });
    } else {
        kprint.write("    {s} = <", .{prop.name});
        for (prop.value._raw) |b| kprint.write("{x:0>2}", .{b});
        kprint.write(">\r", .{});
    }
}

/// True if the bytes are a null-terminated run of printable ASCII (interior
/// nulls allowed, so string lists like `compatible` count too).
fn looksLikeString(raw: []const u8) bool {
    if (raw.len == 0 or raw[raw.len - 1] != 0) return false;
    for (raw[0 .. raw.len - 1]) |c| {
        if (c != 0 and (c < 0x20 or c > 0x7e)) return false;
    }
    return true;
}

/// Read the single u32 value of `name` on `node`, or null if absent.
fn propU32(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !?u32 {
    var it = try node.propertyIterator(dt, .{ .name = name });
    return if (try it.next()) |prop| prop.value.toU32() else null;
}

/// Resolve the boot console from /chosen stdout-path and print the two things a
/// PL011 driver needs from it: the MMIO base (reg) and reference clock. This is
/// the groundwork for configuring the UART from the DTB instead of the bespoke
/// mailbox clock setup in uart.zig.
fn dumpConsole(dt: DeviceTree) !void {
    const chosen = (try dt.nodeFromPath("/chosen")) orelse {
        kprint.write("  no /chosen node\r", .{});
        return;
    };

    // stdout-path = "<alias-or-path>:<options>" (e.g. "serial0:115200n8").
    const stdout_path = blk: {
        var it = try chosen.node.propertyIterator(dt, .{ .name = "stdout-path" });
        const prop = (try it.next()) orelse {
            kprint.write("  /chosen has no stdout-path\r", .{});
            return;
        };
        break :blk prop.value.toString();
    };

    // Strip the ":115200n8" options; the head is an alias or absolute path.
    const node_path = if (std.mem.indexOfScalar(u8, stdout_path, ':')) |i|
        stdout_path[0..i]
    else
        stdout_path;

    const con = (try dt.nodeFromPath(node_path)) orelse {
        kprint.write("  stdout-path \"{s}\" did not resolve\r", .{stdout_path});
        return;
    };

    kprint.write("  stdout-path = \"{s}\" -> {s}\r", .{ stdout_path, con.name });

    // reg is interpreted in the *parent's* (soc) #address-cells/#size-cells.
    const parent = (try con.node.parent(dt)) orelse return;
    const addr_cells = (try parent.node.addressCells(dt)) orelse 2;
    const size_cells = (try parent.node.sizeCells(dt)) orelse 1;

    var reg_it = try con.node.propertyIterator(dt, .{ .name = "reg" });
    if (try reg_it.next()) |reg_prop| {
        var reg = try reg_prop.value.regIterator(addr_cells, size_cells);
        if (reg.next()) |r| kprint.write("    base = 0x{x}, size = 0x{x}\r", .{ r.address, r.size });
    }

    if (try propU32(dt, con.node, "clock-frequency")) |hz| {
        kprint.write("    clock-frequency = {} Hz\r", .{hz});
    }
}

/// First code executed in the higher half. Switching the stack pointer must be
/// done in asm — changing SP inside a normal function would invalidate its
/// frame — so this is a naked trampoline that sets the virtual SP and tail-calls
/// init_arm.
///
/// x0 holds whatever the bootloader left at reset, threaded down through
/// boot1_phys -> enter_higher_half. We only touch x2/sp here, so it flows
/// straight into init_arm's first argument. On raspi3b that value is NOT the
/// DTB (see init_arm); on a generic armv8 board booted via EDK/EFI it will be.
export fn enter_virtual_addressing() callconv(.naked) noreturn {
    asm volatile (
        \\ adrp x2, __kernel_stack_top
        \\ add  x2, x2, #:lo12:__kernel_stack_top
        \\ msr  SPSel, #1            // switch to SP_EL1
        \\ mov  sp, x2
        \\ b    init_arm
    );
}

/// Runs on the virtual kernel stack: zero .bss, then hand off to the kernel.
/// `boot_x0` is the value x0 held at reset, threaded down from boot1_phys.
export fn init_arm(boot_x0: usize) callconv(.c) noreturn {
    @setRuntimeSafety(false);

    // Globals assume .bss is zero. Clear it a word at a time; `volatile` keeps
    // this from being lowered to a memset libcall. __bss_start/_end are
    // 16-byte aligned, so the range is a whole number of usizes.
    const start = @intFromPtr(&__bss_start);
    const end = @intFromPtr(&__bss_end);
    const words: [*]volatile usize = @ptrFromInt(start);
    const count = (end - start) / @sizeOf(usize);
    var i: usize = 0;
    while (i < count) : (i += 1) words[i] = 0;

    const uart = @import("io/uart.zig");
    uart.init();

    // RASPI3B: the machine resets all cores to 0x0 and does NOT hand the DTB to
    // the kernel in x0 (boot_x0 is just leftover reset state), so the device
    // tree is loaded at a fixed physical address by build.zig's loader device
    // and we read it from there.
    //
    // TODO(generic-armv8): once we boot a generic armv8 board via the EDK/EFI
    // protocol, x0 *does* carry the DTB pointer — drop this override and use
    // boot_x0 directly (it is already threaded down from the reset entry).
    _ = boot_x0;
    const fdt_phys: usize = 0x3000000; // must match build.zig loader addr

    // Parse the FDT. fromPtr validates the header (magic, version, block sizes),
    // so a success already proves the blob is really there — no need for a manual
    // magic check. fdt_phys is a *physical* address; read it through the
    // higher-half map (PA + kernel_va_base), not the low identity VA. The FDT
    // header is 8-byte aligned, which fromPtr requires.
    const kernel_va_base: usize = 0xFFFF000000000000;
    const fdt_ptr: [*]align(8) const u8 = @ptrFromInt(fdt_phys + kernel_va_base);

    if (DeviceTree.fromPtr(fdt_ptr)) |fdt| {
        kprint.write("FDT @ 0x{x} ok (v{d}), nodes:\r", .{ fdt_phys, @intFromEnum(fdt.version) });
        dumpFdtNodes(fdt) catch |err| {
            kprint.write("  <node walk failed: {s}>\r", .{@errorName(err)});
        };

        kprint.write("memory nodes:\r", .{});
        dumpMemoryNodes(fdt) catch |err| {
            kprint.write("  <memory walk failed: {s}>\r", .{@errorName(err)});
        };

        kprint.write("console:\r", .{});
        dumpConsole(fdt) catch |err| {
            kprint.write("  <console probe failed: {s}>\r", .{@errorName(err)});
        };
    } else |err| {
        kprint.write("FDT @ 0x{x} parse error: {s}\r", .{ fdt_phys, @errorName(err) });
    }

    // Access our FDT
    //

    // Setup out proc0 structure
    // Setup our thread context
    // Setup uart console

    kmain();
}

/// Terminate via the Arm semihosting SYS_EXIT call (used under QEMU). Declared
/// `extern fn exit() noreturn` by panic.zig and kernel.zig.
export fn exit() noreturn {
    asm volatile (
        \\ mov w0, #0x18             // SYS_EXIT
        \\ mov x1, #0x20000
        \\ add x1, x1, #0x26         // reason = ADP_Stopped_ApplicationExit (0x20026)
        \\ mov x2, #0                // exit code
        \\ stp x1, x2, [sp, #-16]!   // parameter block { reason, code }
        \\ mov x1, sp
        \\ hlt #0xF000               // semihosting trap
        \\ b   .                     // never returns; spin if semihosting is off
    );

    unreachable;
}
