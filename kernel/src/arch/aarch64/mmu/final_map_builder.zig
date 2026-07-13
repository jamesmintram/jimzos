//! Construction of the immutable final kernel direct map.
//!
//! Construction still runs on the bootstrap map, so newly allocated table
//! frames are made visible through `TransitionMapper`. The returned maps have
//! no dependency on that temporary mechanism.

const boot = @import("../../../boot/boot_info.zig");
const phys = @import("phys_range");
const PhysicalAllocator = @import("../../../vm/page_frame_manager.zig").PhysicalAllocator;
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");
const TransitionMapper = @import("transition_mapper.zig").TransitionMapper;
const translation = @import("translation_map.zig");

const page_size: u64 = page_table.page_size;

const normal_attributes = page_table.normal_attributes;
const device_attributes = page_table.device_attributes |
    page_table.privileged_execute_never |
    page_table.unprivileged_execute_never;

extern const __kernel_stack_guard_phys: u8;

pub fn build(
    allocator: *PhysicalAllocator,
    transition: *TransitionMapper,
    info: *const boot.BootInfo,
    early_device: phys.PhysRange,
) !translation.InstalledMaps {
    var builder = try Builder.init(allocator, transition);
    const guard = phys.PhysRange{
        .start = @intFromPtr(&__kernel_stack_guard_phys),
        .end = @intFromPtr(&__kernel_stack_guard_phys) + page_size,
    };

    for (info.memory.constSlice()) |memory| {
        try builder.mapNormalMemory(info, memory, guard);
    }

    const device_range = try early_device.alignedOutward(page_size);
    var device_phys = device_range.start;
    while (device_phys < device_range.end) : (device_phys += page_size) {
        try builder.mapPage(layout.kernel_direct_map_base + device_phys, device_phys, device_attributes);
    }

    const kernel_table_pages = builder.table_pages;
    const idle_user_root = try builder.allocateTable();
    return .{
        .kernel = try translation.TranslationMap.init(
            .kernel,
            builder.root_physical,
            kernel_table_pages,
        ),
        .idle_user = try translation.TranslationMap.init(.user, idle_user_root, 1),
    };
}

const Builder = struct {
    allocator: *PhysicalAllocator,
    transition: *TransitionMapper,
    root_physical: u64,
    table_pages: usize,

    fn init(allocator: *PhysicalAllocator, transition: *TransitionMapper) !Builder {
        var self = Builder{
            .allocator = allocator,
            .transition = transition,
            .root_physical = 0,
            .table_pages = 0,
        };
        self.root_physical = try self.allocateTable();
        return self;
    }

    fn allocateTable(self: *Builder) !u64 {
        const table_phys = self.allocator.allocatePages(1) orelse return error.OutOfPageTableMemory;
        try self.transition.makeNormalAccessible(.{
            .start = table_phys,
            .end = table_phys + page_size,
        });
        @memset(tableFromPhysical(table_phys), 0);
        self.table_pages += 1;
        return table_phys;
    }

    fn mapNormalMemory(
        self: *Builder,
        info: *const boot.BootInfo,
        memory: phys.PhysRange,
        guard: phys.PhysRange,
    ) !void {
        var cursor = memory.start;
        while (cursor < memory.end) {
            const remaining = memory.end - cursor;
            if (cursor % page_table.block_1g_size == 0 and remaining >= page_table.block_1g_size) {
                const candidate = phys.PhysRange{
                    .start = cursor,
                    .end = cursor + page_table.block_1g_size,
                };
                if (!excluded(info, candidate, guard)) {
                    try self.mapBlock1G(layout.kernel_direct_map_base + cursor, cursor, normal_attributes);
                    cursor += page_table.block_1g_size;
                    continue;
                }
            }
            if (cursor % page_table.block_2m_size == 0 and remaining >= page_table.block_2m_size) {
                const candidate = phys.PhysRange{
                    .start = cursor,
                    .end = cursor + page_table.block_2m_size,
                };
                if (!excluded(info, candidate, guard)) {
                    try self.mapBlock2M(layout.kernel_direct_map_base + cursor, cursor, normal_attributes);
                    cursor += page_table.block_2m_size;
                    continue;
                }
            }

            const candidate = phys.PhysRange{ .start = cursor, .end = cursor + page_size };
            if (!excluded(info, candidate, guard)) {
                try self.mapPage(layout.kernel_direct_map_base + cursor, cursor, normal_attributes);
            }
            cursor += page_size;
        }
    }

    fn mapBlock1G(self: *Builder, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
        const l1_phys = try self.ensureNext(
            self.root_physical,
            page_table.indexFor(virtual, page_table.level_0_shift),
        );
        const l1 = tableFromPhysical(l1_phys);
        const index = page_table.indexFor(virtual, page_table.level_1_shift);
        if (l1[index] != 0) return error.MappingConflict;
        l1[index] = page_table.blockDescriptor(physical, attributes);
    }

    fn mapBlock2M(self: *Builder, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
        const l1_phys = try self.ensureNext(
            self.root_physical,
            page_table.indexFor(virtual, page_table.level_0_shift),
        );
        const l2_phys = try self.ensureNext(
            l1_phys,
            page_table.indexFor(virtual, page_table.level_1_shift),
        );
        const l2 = tableFromPhysical(l2_phys);
        const index = page_table.indexFor(virtual, page_table.level_2_shift);
        if (l2[index] != 0) return error.MappingConflict;
        l2[index] = page_table.blockDescriptor(physical, attributes);
    }

    fn mapPage(self: *Builder, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
        const l1_phys = try self.ensureNext(
            self.root_physical,
            page_table.indexFor(virtual, page_table.level_0_shift),
        );
        const l2_phys = try self.ensureNext(
            l1_phys,
            page_table.indexFor(virtual, page_table.level_1_shift),
        );
        const l3_phys = try self.ensureNext(
            l2_phys,
            page_table.indexFor(virtual, page_table.level_2_shift),
        );
        const l3 = tableFromPhysical(l3_phys);
        const index = page_table.indexFor(virtual, page_table.level_3_shift);
        if (l3[index] != 0) return error.MappingConflict;
        l3[index] = page_table.pageDescriptor(physical, attributes);
    }

    fn ensureNext(self: *Builder, parent_phys: u64, index: usize) !u64 {
        const parent = tableFromPhysical(parent_phys);
        const entry = parent[index];
        if (entry == 0) {
            const child_phys = try self.allocateTable();
            parent[index] = page_table.tableDescriptor(child_phys);
            return child_phys;
        }
        if (!page_table.isTableDescriptor(entry)) return error.ExpectedTable;
        return page_table.tableAddress(entry);
    }
};

fn excluded(info: *const boot.BootInfo, candidate: phys.PhysRange, guard: phys.PhysRange) bool {
    if (candidate.overlaps(guard)) return true;
    for (info.reserved.constSlice()) |reservation| {
        if (reservation.no_map and candidate.overlaps(reservation.range)) return true;
    }
    return false;
}

fn tableFromPhysical(physical_address: u64) *[page_table.entries_per_table]page_table.Entry {
    return @ptrFromInt(layout.physicalToVirtual(physical_address) catch unreachable);
}
