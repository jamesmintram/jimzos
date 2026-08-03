//! AArch64 virtual boot stage.
//!
//! boot1 enters here on a temporary translation map. This stage discovers the
//! boot environment, establishes the physical allocator and permanent maps,
//! and preserves the early console across the root switch before handing off
//! to normal kernel initialization.

const DeviceTree = @import("DeviceTree");
const std = @import("std");
const build_options = @import("build_options");
const boot_info = @import("../../boot/boot_info.zig");
const boot_init = @import("../../boot/init.zig");
const diagnostics = @import("../../boot/diagnostics.zig");
const fdt_boot = @import("../../boot/fdt_boot.zig");
const bus = @import("../../bus.zig");
const kprint = @import("../../kprint.zig");
const pl011 = @import("../../drivers/serial/pl011.zig");
const pl011_fdt = @import("../../drivers/serial/pl011_fdt.zig");
const MmioRegion = @import("../../io/mmio_region.zig").MmioRegion;
const vm = @import("../../vm.zig");
const mmu = @import("../mmu.zig");
const platform = @import("platform.zig");
const platform_bootstrap = @import("platform/bootstrap.zig");
const BootstrapDirectMap = @import("mmu/bootstrap_direct_map.zig").BootstrapDirectMap;
const BootstrapTablePageProvider = @import("mmu/bootstrap_table_page_provider.zig").BootstrapTablePageProvider;
const layout = @import("mmu/layout.zig");
const page_table = @import("mmu/page_table.zig");
const translation_map = @import("mmu/translation_map.zig");
const phys = @import("phys_range");

const BootInfo = boot_info.BootInfo;
const ExclusionList = boot_info.FixedList(phys.PhysRange, boot_info.max_reservations + 1);
const Pl011 = pl011.Pl011;
const page_size: u64 = page_table.page_size;

extern var __bss_start: u8;
extern var __bss_end: u8;
extern const __kernel_phys_start: u8;
extern const __kernel_phys_end: u8;
extern const __kernel_stack_guard_phys: u8;

// These objects outlive boot2: the allocator retains the BootInfo pointer and
// the console subsystem retains a pointer to the PL011 object.
var boot_info_storage: BootInfo = undefined;
var system_console: Pl011 = undefined;
var bootstrap_memory_context: u8 = 0;

const bootstrap_memory_vtable: bus.MemorySpace.VTable = .{
    .map = useBootstrapMapping,
};

/// Switch to the virtual kernel stack before entering normal Zig code.
export fn enter_virtual_addressing() callconv(.naked) noreturn {
    asm volatile (
        \\ adrp x2, __kernel_stack_top
        \\ add  x2, x2, #:lo12:__kernel_stack_top
        \\ msr  SPSel, #1
        \\ mov  sp, x2
        \\ b    init_arm
    );
}

/// Clear BSS on the virtual kernel stack, then replace boot1's temporary
/// translation hierarchy before entering normal kernel initialization.
export fn init_arm(boot_x0: usize) callconv(.c) noreturn {
    @setRuntimeSafety(false);

    const start = @intFromPtr(&__bss_start);
    const end = @intFromPtr(&__bss_end);
    const words: [*]volatile usize = @ptrFromInt(start);
    const count = (end - start) / @sizeOf(usize);
    var index: usize = 0;
    while (index < count) : (index += 1) words[index] = 0;

    _ = boot_x0;
    finishBootstrap();
}

fn finishBootstrap() noreturn {
    const fdt_phys = build_options.fdt_phys;
    const fdt_blob = fdt_boot.discover(fdt_phys) catch exit();
    boot_info_storage = buildBootInfoFromFdtBlob(fdt_blob) catch exit();

    const device_tree = fdt_blob.tree;
    const early_pl011_resources = pl011_fdt.discover(device_tree, bootstrapCpuBus()) catch exit();
    const early_pl011_config = early_pl011_resources.map() catch exit();
    platform.prepareEarlyPl011(early_pl011_config.clock_hz) catch exit();
    system_console = Pl011.create(early_pl011_config);
    system_console.configure() catch exit();
    system_console.installAsConsole();

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

    var final_maps = buildFinalMaps(&boot_info_storage) catch exit();
    translation_map.install(&final_maps, vm.get_page_frame_manager()) catch exit();

    // The root switch invalidated the bootstrap UART mapping. Do not use the
    // console until the same PL011 object has a permanent device mapping.
    rebindConsole(device_tree, bus.cpuBus()) catch exit();
    kprint.write("MMU: final FDT map installed using {} table pages\r", .{
        translation_map.current().totalTablePages(),
    });

    boot_init.run(&boot_info_storage);
}

/// Bus view for the small set of device ranges mapped by boot1. Unlike the
/// normal CPU bus this cannot create mappings because the final map and its
/// page-table allocator do not exist yet.
fn bootstrapCpuBus() bus.Bus {
    return .{
        .memory = .{
            .context = &bootstrap_memory_context,
            .vtable = &bootstrap_memory_vtable,
        },
    };
}

fn useBootstrapMapping(_: *anyopaque, range: bus.AddressRange) !MmioRegion {
    const requested = try boot_info.PhysRange.fromStartSize(range.start, range.byte_len);
    inline for (platform_bootstrap.device_ranges) |maybe_mapped| {
        if (maybe_mapped) |mapped| {
            if (mapped.contains(requested)) break;
        }
    } else return error.BootstrapMmioNotMapped;

    const physical_base = std.math.cast(usize, range.start) orelse
        return error.MmioResourceAddressOverflow;
    const byte_len = std.math.cast(usize, range.byte_len) orelse
        return error.MmioResourceSizeOverflow;
    return MmioRegion.init(
        physical_base,
        try mmu.physicalToVirtual(range.start),
        byte_len,
    );
}

fn rebindConsole(fdt: DeviceTree, parent_bus: bus.Bus) !void {
    const resources = try pl011_fdt.discover(fdt, parent_bus);
    const config = try resources.map();
    try system_console.rebind(config);
    kprint.write("console: rebound PL011 at 0x{x}\r", .{config.registers.physicalBase()});
}

fn buildBootInfoFromFdtBlob(fdt: boot_info.FdtBlob) !BootInfo {
    var builder = try fdt_boot.parse(fdt);
    try builder.addReservation(.{
        .start = @intFromPtr(&__kernel_phys_start),
        .end = @intFromPtr(&__kernel_phys_end),
    }, .kernel, false, false);
    try builder.addReservation(
        try boot_info.PhysRange.fromStartSize(fdt.physical_address, fdt.size),
        .fdt,
        false,
        false,
    );
    try builder.addModule(.{
        .range = try boot_info.PhysRange.fromStartSize(
            build_options.kernel_elf_phys,
            build_options.kernel_elf_reserved_size,
        ),
        .used_size = build_options.kernel_elf_reserved_size,
        .kind = .kernel_elf,
    });
    try builder.addModule(.{
        .range = try boot_info.PhysRange.fromStartSize(
            build_options.ext2_phys,
            build_options.ext2_reserved_size,
        ),
        .used_size = build_options.ext2_used_size,
        .kind = .filesystem,
    });
    return builder.finish(vm.allocatorMetadataRequirement);
}

/// Initialize the physical allocator through the bootstrap map, then build the
/// permanent translation roots that will replace it.
fn buildFinalMaps(info: *const BootInfo) !translation_map.InstalledMaps {
    var bootstrap_direct_map = try BootstrapDirectMap.init();
    try bootstrap_direct_map.makeNormalAccessible(info.allocator_metadata);
    try vm.init(info);

    var table_page_provider = BootstrapTablePageProvider.init(
        vm.get_page_frame_manager(),
        &bootstrap_direct_map,
    );
    return buildInitialMaps(&table_page_provider, info);
}

/// Construct the initial permanent kernel map and the empty idle-user map.
fn buildInitialMaps(provider: anytype, info: *const BootInfo) !translation_map.InstalledMaps {
    var kernel_map = try translation_map.TranslationMap.create(.kernel, provider);
    const guard = try phys.PhysRange.fromStartSize(
        @intFromPtr(&__kernel_stack_guard_phys),
        page_size,
    );
    const exclusions = try normalizedExclusions(info, guard);
    try mapKernelDirectMemory(
        &kernel_map,
        provider,
        info.memory.constSlice(),
        exclusions.constSlice(),
    );

    return .{
        .kernel = kernel_map,
        .idle_user = try translation_map.TranslationMap.create(.user, provider),
    };
}

/// Map `memory_ranges - excluded_ranges` with a linear merge. Both inputs must
/// be sorted by start, and excluded ranges must already be merged.
fn mapKernelDirectMemory(
    kernel_map: *translation_map.TranslationMap,
    provider: anytype,
    memory_ranges: []const phys.PhysRange,
    excluded_ranges: []const phys.PhysRange,
) !void {
    var exclusion_index: usize = 0;
    for (memory_ranges) |memory_range| {
        while (exclusion_index < excluded_ranges.len and
            excluded_ranges[exclusion_index].end <= memory_range.start)
        {
            exclusion_index += 1;
        }

        var span_start = memory_range.start;
        while (exclusion_index < excluded_ranges.len and
            excluded_ranges[exclusion_index].start < memory_range.end)
        {
            const excluded_range = excluded_ranges[exclusion_index];
            if (span_start < excluded_range.start) {
                try mapNormalRange(kernel_map, provider, .{
                    .start = span_start,
                    .end = @min(memory_range.end, excluded_range.start),
                });
            }

            span_start = @max(span_start, @min(memory_range.end, excluded_range.end));
            if (excluded_range.end > memory_range.end) break;
            exclusion_index += 1;
        }

        if (span_start < memory_range.end) {
            try mapNormalRange(kernel_map, provider, .{
                .start = span_start,
                .end = memory_range.end,
            });
        }
    }
}

fn mapNormalRange(
    kernel_map: *translation_map.TranslationMap,
    provider: anytype,
    range: phys.PhysRange,
) !void {
    try kernel_map.mapRange(
        provider,
        @intCast(try layout.physicalToVirtual(range.start)),
        range,
        page_table.normal_attributes,
    );
}

fn normalizedExclusions(info: *const BootInfo, guard: phys.PhysRange) !ExclusionList {
    var result: ExclusionList = .{};
    try result.append(guard);
    for (info.reserved.constSlice()) |reservation| {
        if (reservation.no_map) try result.append(reservation.range);
    }

    std.sort.heap(phys.PhysRange, result.slice(), {}, rangeLessThan);
    mergeExclusions(&result);
    return result;
}

fn rangeLessThan(_: void, lhs: phys.PhysRange, rhs: phys.PhysRange) bool {
    return lhs.start < rhs.start or
        (lhs.start == rhs.start and lhs.end < rhs.end);
}

fn mergeExclusions(exclusions: *ExclusionList) void {
    if (exclusions.len < 2) return;

    var output: usize = 0;
    for (exclusions.items[1..exclusions.len]) |range| {
        const previous = &exclusions.items[output];
        if (range.start <= previous.end) {
            previous.end = @max(previous.end, range.end);
        } else {
            output += 1;
            exclusions.items[output] = range;
        }
    }
    exclusions.len = output + 1;
}

/// Terminate via the Arm semihosting SYS_EXIT call used under QEMU.
export fn exit() noreturn {
    asm volatile (
        \\ mov w0, #0x18
        \\ mov x1, #0x20000
        \\ add x1, x1, #0x26
        \\ mov x2, #0
        \\ stp x1, x2, [sp, #-16]!
        \\ mov x1, sp
        \\ hlt #0xF000
        \\ b   .
    );

    unreachable;
}
