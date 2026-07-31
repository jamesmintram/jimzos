const DeviceTree = @import("DeviceTree");
const build_options = @import("build_options");
const kprint = @import("../kprint.zig");
const pl011 = @import("../drivers/serial/pl011.zig");
const pl011_fdt = @import("../drivers/serial/pl011_fdt.zig");
const platform = @import("../arch/aarch64/platform.zig");
const boot = @import("boot_info.zig");
const diagnostics = @import("diagnostics.zig");
const fdt_boot = @import("fdt_boot.zig");
const vm = @import("../vm.zig");
const final_map_builder = @import("../arch/aarch64/mmu/final_map_builder.zig");
const translation_map = @import("../arch/aarch64/mmu/translation_map.zig");
const BootstrapDirectMap = @import("../arch/aarch64/mmu/bootstrap_direct_map.zig").BootstrapDirectMap;
const TableMemory = @import("../arch/aarch64/mmu/table_memory.zig").TableMemory;

const BootInfo = boot.BootInfo;
const Pl011 = pl011.Pl011;

extern fn kmain(boot_info: *const BootInfo) callconv(.c) noreturn;
extern fn exit() noreturn;
extern const __kernel_phys_start: u8;
extern const __kernel_phys_end: u8;

var early_console: Pl011 = undefined;
var attached_console: Pl011 = undefined;
var boot_info_storage: BootInfo = undefined;

fn attachConsoleDriver(fdt: DeviceTree) !void {
    const config = try pl011_fdt.discover(fdt);
    attached_console = try Pl011.adopt(&early_console, config);
    attached_console.installAsConsole();
    kprint.write("console: adopted early PL011 at 0x{x}\r", .{config.registers.physicalBase()});
}

fn buildBootInfoFromFdtBlob(fdt: boot.FdtBlob) !BootInfo {
    var builder = try fdt_boot.parse(fdt);
    try builder.addReservation(.{
        .start = @intFromPtr(&__kernel_phys_start),
        .end = @intFromPtr(&__kernel_phys_end),
    }, .kernel, false, false);
    try builder.addReservation(
        try boot.PhysRange.fromStartSize(fdt.physical_address, fdt.size),
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
    return builder.finish(vm.allocatorMetadataRequirement);
}

/// Initialize the physical allocator through the bootstrap map, then build the
/// translation roots that will replace it.
fn buildFinalMaps(
    info: *const BootInfo,
    required_device_ranges: []const boot.PhysRange,
) !translation_map.InstalledMaps {
    var bootstrap_direct_map = try BootstrapDirectMap.init();
    try bootstrap_direct_map.makeNormalAccessible(info.allocator_metadata);
    try vm.init(info);

    var table_memory = TableMemory.init(
        vm.get_page_frame_manager(),
        &bootstrap_direct_map,
    );
    return final_map_builder.build(&table_memory, info, required_device_ranges);
}

pub fn run() noreturn {
    const fdt_phys = build_options.fdt_phys;
    const fdt_blob = fdt_boot.discover(fdt_phys) catch exit();
    boot_info_storage = buildBootInfoFromFdtBlob(fdt_blob) catch exit();

    const device_tree = fdt_blob.tree;
    const early_pl011_config = pl011_fdt.discover(device_tree) catch exit();
    platform.prepareEarlyPl011(early_pl011_config.clock_hz) catch exit();
    early_console = Pl011.create(early_pl011_config);
    early_console.configure() catch exit();
    early_console.installAsConsole();

    kprint.write("FDT @ 0x{x} ok (v{d}), nodes:\r", .{ fdt_phys, @intFromEnum(device_tree.version) });
    diagnostics.dumpFdtNodes(device_tree) catch |err| {
        kprint.write("  <node walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("memory nodes:\r", .{});
    diagnostics.dumpMemoryNodes(device_tree) catch |err| {
        kprint.write("  <memory walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("early console:\r", .{});
    diagnostics.dumpConsole(early_pl011_config);
    diagnostics.dumpBootInfo(&boot_info_storage);

    const required_device_ranges = [_]boot.PhysRange{
        boot.PhysRange.fromStartSize(
            early_pl011_config.registers.physicalBase(),
            early_pl011_config.registers.size(),
        ) catch exit(),
    };
    const final_maps = buildFinalMaps(&boot_info_storage, &required_device_ranges) catch exit();
    translation_map.install(final_maps) catch exit();
    kprint.write("MMU: final FDT map installed using {} table pages\r", .{final_maps.totalTablePages()});

    attachConsoleDriver(device_tree) catch exit();
    kmain(&boot_info_storage);
}
