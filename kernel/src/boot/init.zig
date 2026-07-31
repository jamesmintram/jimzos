const DeviceTree = @import("DeviceTree");
const build_options = @import("build_options");
const kprint = @import("../kprint.zig");
const mmu = @import("../arch/mmu.zig");
const pl011 = @import("../drivers/serial/pl011.zig");
const pl011_fdt = @import("../drivers/serial/pl011_fdt.zig");
const platform = @import("../arch/aarch64/platform.zig");
const boot = @import("boot_info.zig");
const diagnostics = @import("diagnostics.zig");
const fdt_boot = @import("fdt_boot.zig");
const vm = @import("../vm.zig");
const final_map_builder = @import("../arch/aarch64/mmu/final_map_builder.zig");
const translation_map = @import("../arch/aarch64/mmu/translation_map.zig");
const TransitionMapper = @import("../arch/aarch64/mmu/transition_mapper.zig").TransitionMapper;

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
    diagnostics.dumpFdtNodes(fdt) catch |err| {
        kprint.write("  <node walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("memory nodes:\r", .{});
    diagnostics.dumpMemoryNodes(fdt) catch |err| {
        kprint.write("  <memory walk failed: {s}>\r", .{@errorName(err)});
    };

    kprint.write("early console:\r", .{});
    diagnostics.dumpConsole(early_config);
    diagnostics.dumpBootInfo(&boot_info_storage);

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
