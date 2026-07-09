// aarch64 boot stage 2: higher-half entry/exit glue (MMU on, virtual VAs).
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
const build_options = @import("build_options");
const dt_console = @import("device_tree_console.zig");
const platform = @import("platform.zig");
const Pl011 = @import("../../drivers/serial/pl011.zig").Pl011;

var early_console: Pl011 = undefined;
var attached_console: Pl011 = undefined;

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

fn dumpConsole(config: @import("../../drivers/serial/pl011.zig").Config) void {
    kprint.write("  PL011 base = 0x{x}, size = 0x{x}\r", .{ config.physical_base, config.region_size });
    kprint.write("  clock = {} Hz, baud = {}\r", .{ config.clock_hz, config.baud });
}

fn attachConsoleDriver(fdt: DeviceTree) !void {
    const config = try dt_console.discover(fdt);
    attached_console = try Pl011.adopt(&early_console, config);
    attached_console.installAsConsole();
    kprint.write("console: adopted early PL011 at 0x{x}\r", .{config.physical_base});
}

/// First code executed in the higher half. Switching the stack pointer must be
/// done in asm — changing SP inside a normal function would invalidate its
/// frame — so this is a naked trampoline that sets the virtual SP and tail-calls
/// init_arm.
///
/// x0 is preserved as the platform boot argument while x2 establishes SP_EL1.
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

    _ = boot_x0;
    const fdt_phys = build_options.fdt_phys;

    // fromPtr validates the FDT header, version, and block sizes. fdt_phys is a
    // physical address, so access it through the higher-half mapping. The FDT
    // header is 8-byte aligned as required by the parser.
    const kernel_va_base: usize = 0xFFFF000000000000;
    const fdt_ptr: [*]align(8) const u8 = @ptrFromInt(fdt_phys + kernel_va_base);

    const fdt = DeviceTree.fromPtr(fdt_ptr) catch exit();
    const early_config = dt_console.discover(fdt) catch exit();
    platform.prepareEarlyPl011(early_config.clock_hz) catch exit();
    early_console = Pl011.create(early_config);
    early_console.configure() catch exit();
    early_console.installAsConsole();

    kprint.write("FDT @ 0x{x} ok (v{d}), nodes:\r", .{ fdt_phys, @intFromEnum(fdt.version) });
    dumpFdtNodes(fdt) catch |err| {
        kprint.write("  <node walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("memory nodes:\r", .{});
    dumpMemoryNodes(fdt) catch |err| {
        kprint.write("  <memory walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("early console:\r", .{});
    dumpConsole(early_config);

    attachConsoleDriver(fdt) catch exit();

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
