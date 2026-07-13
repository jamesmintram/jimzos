const std = @import("std");
const DeviceTree = @import("DeviceTree");
const build_options = @import("build_options");
const kprint = @import("../kprint.zig");
const mmu = @import("../arch/mmu.zig");
const pl011 = @import("../drivers/serial/pl011.zig");
const pl011_fdt = @import("../drivers/serial/pl011_fdt.zig");
const platform = @import("../arch/aarch64/platform.zig");
const boot = @import("boot_info.zig");
const fdt_boot = @import("fdt_boot.zig");
const vm = @import("../vm.zig");
const final_map_builder = @import("../arch/aarch64/mmu/final_map_builder.zig");
const translation_map = @import("../arch/aarch64/mmu/translation_map.zig");
const TransitionMapper = @import("../arch/aarch64/mmu/transition_mapper.zig").TransitionMapper;

const BootInfo = boot.BootInfo;
const Config = pl011.Config;
const Pl011 = pl011.Pl011;

extern fn kmain(boot_info: *const BootInfo) callconv(.c) noreturn;
extern fn exit() noreturn;
extern const __kernel_phys_start: u8;
extern const __kernel_phys_end: u8;

var early_console: Pl011 = undefined;
var attached_console: Pl011 = undefined;
var boot_info_storage: BootInfo = undefined;

/// Print the full path of every node in the device tree, root first then all
/// descendants in tree order (nodeIterator walks root's children, so root `/`
/// is printed separately).
fn dumpFdtNodes(dt: DeviceTree) !void {
    var buf: [256]u8 = undefined;

    kprint.write("  {s}\r", .{try DeviceTree.Node.root.path(dt, &buf)});

    var iter = try dt.nodeIterator(.root, .all_children, .any);
    while (try iter.next(dt)) |node| {
        kprint.write("  {s}\r", .{try node.node.path(dt, &buf)});
    }
}

fn dumpMemoryNodes(dt: DeviceTree) !void {
    const address_cells = (try DeviceTree.Node.root.addressCells(dt)) orelse 2;
    const size_cells = (try DeviceTree.Node.root.sizeCells(dt)) orelse 1;

    var nodes = try dt.nodeIterator(.root, .all_children, .{ .name = "memory" });
    while (try nodes.next(dt)) |node| {
        kprint.write("  {s}:\r", .{node.name});

        var properties = try node.node.propertyIterator(dt, .any);
        while (try properties.next()) |property| {
            try printProperty(property, address_cells, size_cells);
        }
    }
}

fn printProperty(property: DeviceTree.Property, address_cells: u32, size_cells: u32) !void {
    if (std.mem.eql(u8, property.name, "reg")) {
        kprint.write("    {s} =", .{property.name});
        var registers = try property.value.regIterator(address_cells, size_cells);
        while (registers.next()) |register| {
            kprint.write(" <0x{x} 0x{x}>", .{ register.address, register.size });
        }
        kprint.write("\r", .{});
    } else if (looksLikeString(property.value._raw)) {
        kprint.write("    {s} = \"{s}\"\r", .{ property.name, property.value.toString() });
    } else {
        kprint.write("    {s} = <", .{property.name});
        for (property.value._raw) |byte| kprint.write("{x:0>2}", .{byte});
        kprint.write(">\r", .{});
    }
}

fn looksLikeString(raw: []const u8) bool {
    if (raw.len == 0 or raw[raw.len - 1] != 0) return false;
    for (raw[0 .. raw.len - 1]) |byte| {
        if (byte != 0 and (byte < 0x20 or byte > 0x7e)) return false;
    }
    return true;
}

fn dumpConsole(config: Config) void {
    kprint.write("  PL011 base = 0x{x}, size = 0x{x}\r", .{
        config.registers.physicalBase(),
        config.registers.size(),
    });
    kprint.write("  clock = {} Hz, baud = {}\r", .{ config.clock_hz, config.baud });
}

fn attachConsoleDriver(fdt: DeviceTree) !void {
    const config = try pl011_fdt.discover(fdt);
    attached_console = try Pl011.adopt(&early_console, config);
    attached_console.installAsConsole();
    kprint.write("console: adopted early PL011 at 0x{x}\r", .{config.registers.physicalBase()});
}

fn finishBootInfo(mut_builder: boot.Builder) !BootInfo {
    var builder = mut_builder;
    try builder.addReservation(.{
        .start = @intFromPtr(&__kernel_phys_start),
        .end = @intFromPtr(&__kernel_phys_end),
    }, .kernel, false, false);
    try builder.addReservation(
        try boot.PhysRange.fromStartSize(builder.fdt.physical_address, builder.fdt.size),
        .fdt,
        false,
        false,
    );
    try builder.addModule(.{
        .range = try boot.PhysRange.fromStartSize(
            build_options.kernel_elf_phys,
            build_options.kernel_elf_reserved_size,
        ),
        .used_size = build_options.kernel_elf_reserved_size,
        .kind = .kernel_elf,
    });
    try builder.addModule(.{
        .range = try boot.PhysRange.fromStartSize(
            build_options.ext2_phys,
            build_options.ext2_reserved_size,
        ),
        .used_size = build_options.ext2_used_size,
        .kind = .filesystem,
    });
    try builder.normalize();
    try vm.reserveMetadata(&builder);
    return builder.finalize();
}

fn dumpBootInfo(info: *const BootInfo) void {
    kprint.write("boot memory: {} MiB reported, {} MiB usable\r", .{
        info.totalMemoryBytes() / (1024 * 1024),
        info.totalUsableBytes() / (1024 * 1024),
    });
    for (info.memory.constSlice()) |range| {
        kprint.write("  RAM  [0x{x}, 0x{x})\r", .{ range.start, range.end });
    }
    for (info.reserved.constSlice()) |reservation| {
        kprint.write("  RSV  [0x{x}, 0x{x}) {s}{s}\r", .{
            reservation.range.start,
            reservation.range.end,
            @tagName(reservation.kind),
            if (reservation.no_map) " no-map" else "",
        });
    }
    for (info.usable.constSlice()) |range| {
        kprint.write("  FREE [0x{x}, 0x{x})\r", .{ range.start, range.end });
    }
    kprint.write("boot CPUs: {}, boot id 0x{x}\r", .{ info.cpus.len, info.boot_cpu_id });
}

pub fn run() noreturn {
    const fdt_phys = build_options.fdt_phys;
    const builder = fdt_boot.discover(fdt_phys) catch exit();
    const fdt = builder.fdt.tree;
    boot_info_storage = finishBootInfo(builder) catch exit();
    const early_config = pl011_fdt.discover(fdt) catch exit();
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
    dumpBootInfo(&boot_info_storage);

    var transition = TransitionMapper.init() catch exit();
    transition.makeNormalAccessible(boot_info_storage.allocator_metadata) catch exit();
    vm.init(&boot_info_storage) catch exit();
    const final_maps = final_map_builder.build(
        vm.get_page_frame_manager(),
        &transition,
        &boot_info_storage,
        boot.PhysRange.fromStartSize(
            early_config.registers.physicalBase(),
            early_config.registers.size(),
        ) catch exit(),
    ) catch exit();
    translation_map.install(final_maps) catch exit();
    transition.finish();
    early_console.useMappedRegisters(
        mmu.physicalToVirtual(early_config.registers.physicalBase()) catch exit(),
    ) catch exit();
    kprint.write("MMU: final FDT map installed using {} table pages\r", .{final_maps.totalTablePages()});

    attachConsoleDriver(fdt) catch exit();
    kmain(&boot_info_storage);
}
