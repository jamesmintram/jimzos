const std = @import("std");
const boot = @import("../../../boot/boot_info.zig");
const phys = @import("phys_range");
const PhysicalAllocator = @import("../../../vm/page_frame_manager.zig").PhysicalAllocator;
const transition_mapper = @import("transition_mapper.zig");

const kernel_va_base: u64 = 0xffff000000000000;
const entries_per_table = 512;
const page_size = phys.page_size;
const block_2m: u64 = 2 * 1024 * 1024;
const block_1g: u64 = 1024 * 1024 * 1024;

const descriptor_valid: u64 = 1;
const descriptor_table_or_page: u64 = 3;
const access_flag: u64 = 1 << 10;
const outer_shareable: u64 = 2 << 8;
const inner_shareable: u64 = 3 << 8;
const attr_normal: u64 = 0 << 2;
const attr_device: u64 = 1 << 2;
const privileged_execute_never: u64 = 1 << 53;
const unprivileged_execute_never: u64 = 1 << 54;

const normal_flags = access_flag | inner_shareable | attr_normal;
const device_flags = access_flag | outer_shareable | attr_device |
    privileged_execute_never | unprivileged_execute_never;

extern const __kernel_stack_guard_phys: u8;

pub const Result = struct {
    root_physical: u64,
    table_pages: usize,
};

pub fn install(
    allocator: *PhysicalAllocator,
    info: *const boot.BootInfo,
    early_device: phys.PhysRange,
) !Result {
    var mapper = try Mapper.init(allocator);
    const guard = phys.PhysRange{
        .start = @intFromPtr(&__kernel_stack_guard_phys),
        .end = @intFromPtr(&__kernel_stack_guard_phys) + page_size,
    };

    for (info.memory.constSlice()) |memory| {
        try mapper.mapNormalMemory(info, memory, guard);
    }

    const device_range = try early_device.alignedOutward(page_size);
    var device_phys = device_range.start;
    while (device_phys < device_range.end) : (device_phys += page_size) {
        try mapper.mapPage(kernel_va_base + device_phys, device_phys, device_flags);
    }

    const empty_low_root = try mapper.allocateTable();
    switchRoots(mapper.root_physical, empty_low_root);
    return .{
        .root_physical = mapper.root_physical,
        .table_pages = mapper.table_pages,
    };
}

const Mapper = struct {
    allocator: *PhysicalAllocator,
    root_physical: u64,
    table_pages: usize,

    fn init(allocator: *PhysicalAllocator) !Mapper {
        var self = Mapper{
            .allocator = allocator,
            .root_physical = 0,
            .table_pages = 0,
        };
        self.root_physical = try self.allocateTable();
        return self;
    }

    fn allocateTable(self: *Mapper) !u64 {
        const table_phys = self.allocator.allocatePages(1) orelse return error.OutOfPageTableMemory;
        try transition_mapper.mapTemporaryNormal(.{
            .start = table_phys,
            .end = table_phys + page_size,
        });
        const table = tableFromPhysical(table_phys);
        @memset(table, 0);
        self.table_pages += 1;
        return table_phys;
    }

    fn mapNormalMemory(
        self: *Mapper,
        info: *const boot.BootInfo,
        memory: phys.PhysRange,
        guard: phys.PhysRange,
    ) !void {
        var cursor = memory.start;
        while (cursor < memory.end) {
            const remaining = memory.end - cursor;
            if (cursor % block_1g == 0 and remaining >= block_1g) {
                const candidate = phys.PhysRange{ .start = cursor, .end = cursor + block_1g };
                if (!excluded(info, candidate, guard)) {
                    try self.mapBlock1G(kernel_va_base + cursor, cursor, normal_flags);
                    cursor += block_1g;
                    continue;
                }
            }
            if (cursor % block_2m == 0 and remaining >= block_2m) {
                const candidate = phys.PhysRange{ .start = cursor, .end = cursor + block_2m };
                if (!excluded(info, candidate, guard)) {
                    try self.mapBlock2M(kernel_va_base + cursor, cursor, normal_flags);
                    cursor += block_2m;
                    continue;
                }
            }

            const page = phys.PhysRange{ .start = cursor, .end = cursor + page_size };
            if (!excluded(info, page, guard)) {
                try self.mapPage(kernel_va_base + cursor, cursor, normal_flags);
            }
            cursor += page_size;
        }
    }

    fn mapBlock1G(self: *Mapper, virtual: u64, physical: u64, flags: u64) !void {
        const l1_phys = try self.ensureNext(self.root_physical, indexFor(virtual, 39));
        const l1 = tableFromPhysical(l1_phys);
        const index = indexFor(virtual, 30);
        if (l1[index] != 0) return error.MappingConflict;
        l1[index] = physical | flags | descriptor_valid;
    }

    fn mapBlock2M(self: *Mapper, virtual: u64, physical: u64, flags: u64) !void {
        const l1_phys = try self.ensureNext(self.root_physical, indexFor(virtual, 39));
        const l2_phys = try self.ensureNext(l1_phys, indexFor(virtual, 30));
        const l2 = tableFromPhysical(l2_phys);
        const index = indexFor(virtual, 21);
        if (l2[index] != 0) return error.MappingConflict;
        l2[index] = physical | flags | descriptor_valid;
    }

    fn mapPage(self: *Mapper, virtual: u64, physical: u64, flags: u64) !void {
        const l1_phys = try self.ensureNext(self.root_physical, indexFor(virtual, 39));
        const l2_phys = try self.ensureNext(l1_phys, indexFor(virtual, 30));
        const l3_phys = try self.ensureNext(l2_phys, indexFor(virtual, 21));
        const l3 = tableFromPhysical(l3_phys);
        const index = indexFor(virtual, 12);
        if (l3[index] != 0) return error.MappingConflict;
        l3[index] = physical | flags | descriptor_table_or_page;
    }

    fn ensureNext(self: *Mapper, parent_phys: u64, index: usize) !u64 {
        const parent = tableFromPhysical(parent_phys);
        const entry = parent[index];
        if (entry == 0) {
            const child_phys = try self.allocateTable();
            parent[index] = child_phys | descriptor_table_or_page;
            return child_phys;
        }
        if (entry & descriptor_table_or_page != descriptor_table_or_page) return error.ExpectedTable;
        return entry & 0x0000fffffffff000;
    }
};

fn excluded(info: *const boot.BootInfo, candidate: phys.PhysRange, guard: phys.PhysRange) bool {
    if (candidate.overlaps(guard)) return true;
    for (info.reserved.constSlice()) |reservation| {
        if (reservation.no_map and candidate.overlaps(reservation.range)) return true;
    }
    return false;
}

fn indexFor(virtual: u64, shift: u6) usize {
    return @intCast((virtual >> shift) & (entries_per_table - 1));
}

fn tableFromPhysical(physical_address: u64) *[entries_per_table]u64 {
    return @ptrFromInt(@as(usize, @intCast(kernel_va_base + physical_address)));
}

fn switchRoots(high_root: u64, low_root: u64) void {
    asm volatile (
        \\ dsb ishst
        \\ msr ttbr1_el1, %[high]
        \\ msr ttbr0_el1, %[low]
        \\ isb
        \\ tlbi vmalle1
        \\ dsb ish
        \\ isb
        :
        : [high] "r" (@as(usize, @intCast(high_root))),
          [low] "r" (@as(usize, @intCast(low_root))),
        : .{ .memory = true });
}
