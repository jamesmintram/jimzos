//! Short-lived mutation of one AArch64 stage-1 translation-table hierarchy.
//!
//! A `TranslationMap` owns the root and all reachable table pages. This module
//! only walks that hierarchy and obtains new table pages from a provider.

const std = @import("std");
const builtin = @import("builtin");
const phys = @import("phys_range");
const page_table = @import("page_table.zig");

const page_size: u64 = page_table.page_size;

pub fn TableEditor(comptime TablePageProvider: type) type {
    return struct {
        provider: *TablePageProvider,
        root_physical: u64,
        allocated_table_pages: usize,

        const Self = @This();

        pub fn init(
            provider: *TablePageProvider,
            root_physical: u64,
        ) !Self {
            if (root_physical == 0 or root_physical % page_size != 0) {
                return error.InvalidTranslationRoot;
            }
            return .{
                .provider = provider,
                .root_physical = root_physical,
                .allocated_table_pages = 0,
            };
        }

        pub fn allocatedTablePageCount(self: *const Self) usize {
            return self.allocated_table_pages;
        }

        /// Map a contiguous physical range, using the largest valid descriptors
        /// permitted by the virtual and physical alignment at each position.
        pub fn mapRange(
            self: *Self,
            virtual_start: u64,
            physical: phys.PhysRange,
            attributes: page_table.Entry,
        ) !void {
            try validateRange(virtual_start, physical);

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

        /// Map a range using base-page descriptors only. This conservative form
        /// never replaces or splits an existing block descriptor.
        pub fn mapPageRange(
            self: *Self,
            virtual_start: u64,
            physical: phys.PhysRange,
            attributes: page_table.Entry,
        ) !void {
            try validateRange(virtual_start, physical);

            var virtual = virtual_start;
            var physical_cursor = physical.start;
            while (physical_cursor < physical.end) {
                try self.mapPage(virtual, physical_cursor, attributes);
                virtual += page_size;
                physical_cursor += page_size;
            }
        }

        fn allocateTable(self: *Self) !u64 {
            const physical = try self.provider.allocateZeroed();
            self.allocated_table_pages += 1;
            return physical;
        }

        fn mapBlock1G(self: *Self, virtual: u64, physical: u64, attributes: page_table.Entry) !void {
            const l1_phys = try self.ensureNext(
                self.root_physical,
                page_table.indexFor(virtual, page_table.level_0_shift),
            );
            const l1 = self.provider.tableAt(l1_phys);
            const index = page_table.indexFor(virtual, page_table.level_1_shift);
            try page_table.ensureDescriptor(
                &l1[index],
                page_table.blockDescriptor(physical, attributes),
            );
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
            const l2 = self.provider.tableAt(l2_phys);
            const index = page_table.indexFor(virtual, page_table.level_2_shift);
            try page_table.ensureDescriptor(
                &l2[index],
                page_table.blockDescriptor(physical, attributes),
            );
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
            const l3 = self.provider.tableAt(l3_phys);
            const index = page_table.indexFor(virtual, page_table.level_3_shift);
            try page_table.ensureDescriptor(
                &l3[index],
                page_table.pageDescriptor(physical, attributes),
            );
        }

        fn ensureNext(self: *Self, parent_phys: u64, index: usize) !u64 {
            const parent = self.provider.tableAt(parent_phys);
            const entry = parent[index];
            if (entry == 0) {
                const child_phys = try self.allocateTable();
                publishChildTable();
                parent[index] = page_table.tableDescriptor(child_phys);
                return child_phys;
            }
            if (!page_table.isTableDescriptor(entry)) return error.ExpectedTable;
            return page_table.tableAddress(entry);
        }
    };
}

fn validateRange(virtual_start: u64, physical: phys.PhysRange) !void {
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
}

/// A child must be completely initialized before its descriptor becomes
/// observable through the parent. This ordering is safe for both private and
/// already-published roots, so callers do not select a publication mode.
fn publishChildTable() void {
    if (builtin.cpu.arch == .aarch64) {
        asm volatile ("dsb ishst" ::: .{ .memory = true });
    }
}

fn canMapBlock(virtual: u64, physical: u64, remaining: u64, block_size: u64) bool {
    return virtual % block_size == 0 and
        physical % block_size == 0 and
        remaining >= block_size;
}

const TestTablePageProvider = struct {
    const table_capacity = 8;
    const Table = [page_table.entries_per_table]page_table.Entry;

    tables: [table_capacity]Table,
    allocated: usize,

    fn init() TestTablePageProvider {
        var self: TestTablePageProvider = undefined;
        self.allocated = 0;
        @memset(std.mem.asBytes(&self.tables), 0);
        return self;
    }

    pub fn allocateZeroed(self: *TestTablePageProvider) !u64 {
        if (self.allocated == table_capacity) return error.OutOfPageTableMemory;
        const index = self.allocated;
        self.allocated += 1;
        @memset(&self.tables[index], 0);
        return (@as(u64, @intCast(index)) + 1) * page_size;
    }

    pub fn tableAt(self: *TestTablePageProvider, physical: u64) *Table {
        std.debug.assert(physical != 0 and physical % page_size == 0);
        const index: usize = @intCast(physical / page_size - 1);
        std.debug.assert(index < self.allocated);
        return &self.tables[index];
    }
};

test "table editor maps and reuses a base-page hierarchy" {
    var provider = TestTablePageProvider.init();
    const root = try provider.allocateZeroed();
    const Editor = TableEditor(TestTablePageProvider);
    var editor = try Editor.init(&provider, root);

    const virtual: u64 = 0x4000_0000;
    const physical: u64 = 0x8000_0000;
    try editor.mapPageRange(
        virtual,
        try phys.PhysRange.fromStartSize(physical, page_size),
        page_table.normal_attributes,
    );

    try std.testing.expectEqual(@as(usize, 3), editor.allocatedTablePageCount());
    try std.testing.expectEqual(@as(usize, 4), provider.allocated);

    const l0 = provider.tableAt(root);
    const l1_physical = page_table.tableAddress(
        l0[page_table.indexFor(virtual, page_table.level_0_shift)],
    );
    const l1 = provider.tableAt(l1_physical);
    const l2_physical = page_table.tableAddress(
        l1[page_table.indexFor(virtual, page_table.level_1_shift)],
    );
    const l2 = provider.tableAt(l2_physical);
    const l3_physical = page_table.tableAddress(
        l2[page_table.indexFor(virtual, page_table.level_2_shift)],
    );
    const l3 = provider.tableAt(l3_physical);
    try std.testing.expectEqual(
        page_table.pageDescriptor(physical, page_table.normal_attributes),
        l3[page_table.indexFor(virtual, page_table.level_3_shift)],
    );

    try editor.mapPageRange(
        virtual + page_size,
        try phys.PhysRange.fromStartSize(physical + page_size, page_size),
        page_table.normal_attributes,
    );
    try std.testing.expectEqual(@as(usize, 3), editor.allocatedTablePageCount());
    try std.testing.expectEqual(@as(usize, 4), provider.allocated);

    try editor.mapPageRange(
        virtual,
        try phys.PhysRange.fromStartSize(physical, page_size),
        page_table.normal_attributes,
    );
    try std.testing.expectError(
        error.MappingConflict,
        editor.mapPageRange(
            virtual,
            try phys.PhysRange.fromStartSize(physical + page_size, page_size),
            page_table.normal_attributes,
        ),
    );
}

test "table editor selects a one-gibibyte block when aligned" {
    var provider = TestTablePageProvider.init();
    const root = try provider.allocateZeroed();
    const Editor = TableEditor(TestTablePageProvider);
    var editor = try Editor.init(&provider, root);

    try editor.mapRange(
        0,
        try phys.PhysRange.fromStartSize(0, page_table.block_1g_size),
        page_table.normal_attributes,
    );

    try std.testing.expectEqual(@as(usize, 1), editor.allocatedTablePageCount());
    try std.testing.expectEqual(@as(usize, 2), provider.allocated);
    const l0 = provider.tableAt(root);
    const l1 = provider.tableAt(page_table.tableAddress(l0[0]));
    try std.testing.expectEqual(
        page_table.blockDescriptor(0, page_table.normal_attributes),
        l1[0],
    );
}
