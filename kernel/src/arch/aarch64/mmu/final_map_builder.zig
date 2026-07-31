//! Policy for constructing the immutable final kernel and idle-user maps.
//!
//! Generic page-table mutation lives in `AddressSpaceBuilder`; this module
//! decides which boot-time ranges belong in each address space.

const std = @import("std");
const boot = @import("../../../boot/boot_info.zig");
const phys = @import("phys_range");
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");
const AddressSpaceBuilder = @import("address_space_builder.zig").AddressSpaceBuilder;
const TableMemory = @import("table_memory.zig").TableMemory;
const translation = @import("translation_map.zig");

const page_size: u64 = page_table.page_size;
const ExclusionList = boot.FixedList(phys.PhysRange, boot.max_reservations + 1);

const normal_attributes = page_table.normal_attributes;
const device_attributes = page_table.device_attributes |
    page_table.privileged_execute_never |
    page_table.unprivileged_execute_never;

extern const __kernel_stack_guard_phys: u8;

pub fn build(
    table_memory: *TableMemory,
    info: *const boot.BootInfo,
    required_device_ranges: []const phys.PhysRange,
) !translation.InstalledMaps {
    var kernel_space = try AddressSpaceBuilder.init(table_memory);
    const guard = try phys.PhysRange.fromStartSize(
        @intFromPtr(&__kernel_stack_guard_phys),
        page_size,
    );
    const exclusions = try normalizedExclusions(info, guard);
    try mapKernelDirectMemory(
        &kernel_space,
        info.memory.constSlice(),
        exclusions.constSlice(),
    );

    for (required_device_ranges) |required_range| {
        const device_range = try required_range.alignedOutward(page_size);
        try kernel_space.mapRange(
            @intCast(try layout.physicalToVirtual(device_range.start)),
            device_range,
            device_attributes,
        );
    }

    const idle_user_space = try AddressSpaceBuilder.init(table_memory);
    return .{
        .kernel = try translation.TranslationMap.init(
            .kernel,
            kernel_space.rootPhysical(),
            kernel_space.tablePageCount(),
        ),
        .idle_user = try translation.TranslationMap.init(
            .user,
            idle_user_space.rootPhysical(),
            idle_user_space.tablePageCount(),
        ),
    };
}

/// Map `memory_ranges - excluded_ranges` with a linear merge. Both inputs must
/// be sorted by start, and excluded ranges must already be merged.
fn mapKernelDirectMemory(
    address_space: *AddressSpaceBuilder,
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
                try mapNormalRange(address_space, .{
                    .start = span_start,
                    .end = @min(memory_range.end, excluded_range.start),
                });
            }

            span_start = @max(span_start, @min(memory_range.end, excluded_range.end));
            if (excluded_range.end > memory_range.end) break;
            exclusion_index += 1;
        }

        if (span_start < memory_range.end) {
            try mapNormalRange(address_space, .{
                .start = span_start,
                .end = memory_range.end,
            });
        }
    }
}

fn mapNormalRange(address_space: *AddressSpaceBuilder, range: phys.PhysRange) !void {
    try address_space.mapRange(
        @intCast(try layout.physicalToVirtual(range.start)),
        range,
        normal_attributes,
    );
}

fn normalizedExclusions(
    info: *const boot.BootInfo,
    guard: phys.PhysRange,
) !ExclusionList {
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
