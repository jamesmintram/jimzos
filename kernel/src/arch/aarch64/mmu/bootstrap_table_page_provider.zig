//! Boot-only allocation and access for final translation-table pages.
//!
//! Newly allocated frames are not necessarily visible in the temporary direct
//! map, so this provider exposes each frame before zeroing or editing it.

const phys = @import("phys_range");
const PhysicalAllocator = @import("../../../vm/page_frame_manager.zig").PhysicalAllocator;
const BootstrapDirectMap = @import("bootstrap_direct_map.zig").BootstrapDirectMap;
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");

const page_size: u64 = page_table.page_size;

pub const Table = [page_table.entries_per_table]page_table.Entry;

pub const BootstrapTablePageProvider = struct {
    allocator: *PhysicalAllocator,
    direct_map: *BootstrapDirectMap,

    const Self = @This();

    pub fn init(
        allocator: *PhysicalAllocator,
        direct_map: *BootstrapDirectMap,
    ) Self {
        return .{
            .allocator = allocator,
            .direct_map = direct_map,
        };
    }

    pub fn allocateZeroed(self: *Self) !u64 {
        const physical = self.allocator.allocatePages(1) orelse return error.OutOfPageTableMemory;
        try self.direct_map.makeNormalAccessible(
            try phys.PhysRange.fromStartSize(physical, page_size),
        );

        const entries = self.tableAt(physical);
        @memset(entries, 0);
        return physical;
    }

    pub fn tableAt(_: *const Self, physical: u64) *Table {
        return @ptrFromInt(layout.physicalToVirtual(physical) catch unreachable);
    }
};
