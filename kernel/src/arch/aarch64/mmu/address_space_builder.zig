//! Mutable construction of an AArch64 stage-1 address space.
//!
//! This module owns page-table mechanics only. It has no knowledge of boot
//! memory policy, reservations, the kernel direct map, or device discovery.

const std = @import("std");
const phys = @import("phys_range");
const page_table = @import("page_table.zig");
const TableMemory = @import("table_memory.zig").TableMemory;

const page_size: u64 = page_table.page_size;

pub const AddressSpaceBuilder = struct {
    table_memory: *TableMemory,
    root_physical: u64,
    table_pages: usize,

    const Self = @This();

    pub fn init(table_memory: *TableMemory) !Self {
        var self = Self{
            .table_memory = table_memory,
            .root_physical = 0,
            .table_pages = 0,
        };
        self.root_physical = try self.allocateTable();
        return self;
    }

    pub fn rootPhysical(self: *const Self) u64 {
        return self.root_physical;
    }

    pub fn tablePageCount(self: *const Self) usize {
        return self.table_pages;
    }

    /// Map a contiguous physical range, using the largest valid descriptors
    /// permitted by the virtual and physical alignment at each position.
    pub fn mapRange(
        self: *Self,
        virtual_start: u64,
        physical: phys.PhysRange,
        attributes: page_table.Entry,
    ) !void {
        if (physical.start >= physical.end) return error.EmptyMappingRange;
        if (virtual_start % page_size != 0 or
            physical.start % page_size != 0 or
            physical.end % page_size != 0)
        {
            return error.UnalignedMappingRange;
        }
        _ = std.math.add(u64, virtual_start, physical.size()) catch {
            return error.VirtualMappingRangeOverflow;
        };

        var virtual = virtual_start;
        var physical_cursor = physical.start;
        while (physical_cursor < physical.end) {
            const remaining = physical.end - physical_cursor;
            if (canMapBlock(virtual, physical_cursor, remaining, page_table.block_1g_size)) {
                try self.mapBlock1G(virtual, physical_cursor, attributes);
                virtual += page_table.block_1g_size;
                physical_cursor += page_table.block_1g_size;
            } else if (canMapBlock(virtual, physical_cursor, remaining, page_table.block_2m_size)) {
                try self.mapBlock2M(virtual, physical_cursor, attributes);
                virtual += page_table.block_2m_size;
                physical_cursor += page_table.block_2m_size;
            } else {
                try self.mapPage(virtual, physical_cursor, attributes);
                virtual += page_size;
                physical_cursor += page_size;
            }
        }
    }

    fn allocateTable(self: *Self) !u64 {
        const physical = try self.table_memory.allocateZeroed();
        self.table_pages += 1;
        return physical;
    }

    fn mapBlock1G(self: *Self, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
        const l1_phys = try self.ensureNext(
            self.root_physical,
            page_table.indexFor(virtual, page_table.level_0_shift),
        );
        const l1 = self.table_memory.tableAt(l1_phys);
        const index = page_table.indexFor(virtual, page_table.level_1_shift);
        if (l1[index] != 0) return error.MappingConflict;
        l1[index] = page_table.blockDescriptor(physical, attributes);
    }

    fn mapBlock2M(self: *Self, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
        const l1_phys = try self.ensureNext(
            self.root_physical,
            page_table.indexFor(virtual, page_table.level_0_shift),
        );
        const l2_phys = try self.ensureNext(
            l1_phys,
            page_table.indexFor(virtual, page_table.level_1_shift),
        );
        const l2 = self.table_memory.tableAt(l2_phys);
        const index = page_table.indexFor(virtual, page_table.level_2_shift);
        if (l2[index] != 0) return error.MappingConflict;
        l2[index] = page_table.blockDescriptor(physical, attributes);
    }

    fn mapPage(self: *Self, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
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
        const l3 = self.table_memory.tableAt(l3_phys);
        const index = page_table.indexFor(virtual, page_table.level_3_shift);
        if (l3[index] != 0) return error.MappingConflict;
        l3[index] = page_table.pageDescriptor(physical, attributes);
    }

    fn ensureNext(self: *Self, parent_phys: u64, index: usize) !u64 {
        const parent = self.table_memory.tableAt(parent_phys);
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

fn canMapBlock(virtual: u64, physical: u64, remaining: u64, block_size: u64) bool {
    return virtual % block_size == 0 and
        physical % block_size == 0 and
        remaining >= block_size;
}
