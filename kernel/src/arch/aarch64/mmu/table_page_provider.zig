//! Runtime allocation and access for AArch64 translation-table pages.
//!
//! Frames returned by the physical allocator are covered by the permanent
//! kernel direct map, so the provider can zero and edit them in place.

const PhysicalAllocator = @import("../../../vm/page_frame_manager.zig").PhysicalAllocator;
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");

pub const Table = [page_table.entries_per_table]page_table.Entry;

pub const TablePageProvider = struct {
    allocator: *PhysicalAllocator,

    const Self = @This();

    pub fn init(allocator: *PhysicalAllocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn allocateZeroed(self: *Self) !u64 {
        const physical = self.allocator.allocatePages(1) orelse return error.OutOfPageTableMemory;
        const entries = self.tableAt(physical);
        @memset(entries, 0);
        return physical;
    }

    pub fn tableAt(_: *const Self, physical: u64) *Table {
        return @ptrFromInt(layout.physicalToVirtual(physical) catch unreachable);
    }
};
