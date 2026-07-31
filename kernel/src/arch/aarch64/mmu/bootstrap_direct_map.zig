//! Access to normal physical memory through the active bootstrap direct map.
//!
//! This extends the linker-reserved root installed by `boot1_phys`. Boot
//! orchestration keeps it in lexical scope until the final TTBR roots replace
//! that bootstrap root.

const phys = @import("phys_range");
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");

const page_size: u64 = page_table.page_size;

extern const __page_tables_phys_start: u8;
extern const __page_tables_phys_end: u8;

pub const BootstrapDirectMap = struct {
    root_physical: u64,
    arena: TableArena,

    const Self = @This();

    pub fn init() !Self {
        const pool_start: u64 = @intFromPtr(&__page_tables_phys_start);
        const pool_end: u64 = @intFromPtr(&__page_tables_phys_end);
        if (pool_start >= pool_end or pool_start % page_size != 0 or pool_end % page_size != 0) {
            return error.InvalidBootstrapPageTablePool;
        }

        const midpoint = pool_start + (pool_end - pool_start) / 2;
        if (midpoint % page_size != 0) return error.InvalidBootstrapPageTablePool;

        return .{
            .root_physical = pool_start,
            .arena = .{ .next = midpoint, .end = pool_end },
        };
    }

    pub fn makeNormalAccessible(self: *Self, range: phys.PhysRange) !void {
        if (range.start % page_size != 0 or range.end % page_size != 0) {
            return error.UnalignedBootstrapRange;
        }

        var cursor = range.start;
        while (cursor < range.end) : (cursor += page_size) {
            try mapPage(
                self.root_physical,
                @intCast(try layout.physicalToVirtual(cursor)),
                cursor,
                page_table.normal_attributes,
                &self.arena,
            );
        }
        flushTranslations();
    }
};

const TableArena = struct {
    next: u64,
    end: u64,

    fn allocate(self: *TableArena) !u64 {
        if (self.next + page_size > self.end) return error.BootstrapPageTablesExhausted;
        const result = self.next;
        self.next += page_size;
        @memset(tableFromPhysical(result), 0);
        return result;
    }
};

fn mapPage(
    root: u64,
    virtual: u64,
    physical: u64,
    attributes: page_table.Entry,
    arena: *TableArena,
) !void {
    const l1 = try ensureNext(root, page_table.indexFor(virtual, page_table.level_0_shift), arena);
    const l2 = try ensureNext(l1, page_table.indexFor(virtual, page_table.level_1_shift), arena);
    const l3 = try ensureNext(l2, page_table.indexFor(virtual, page_table.level_2_shift), arena);
    tableFromPhysical(l3)[page_table.indexFor(virtual, page_table.level_3_shift)] =
        page_table.pageDescriptor(physical, attributes);
}

fn ensureNext(parent_phys: u64, index: usize, arena: *TableArena) !u64 {
    const parent = tableFromPhysical(parent_phys);
    const entry = parent[index];
    if (entry != 0) {
        if (!page_table.isTableDescriptor(entry)) return error.ExpectedBootstrapTable;
        return page_table.tableAddress(entry);
    }
    const child = try arena.allocate();
    parent[index] = page_table.tableDescriptor(child);
    return child;
}

fn tableFromPhysical(physical_address: u64) *[page_table.entries_per_table]page_table.Entry {
    return @ptrFromInt(layout.physicalToVirtual(physical_address) catch unreachable);
}

fn flushTranslations() void {
    asm volatile (
        \\ dsb ishst
        \\ tlbi vmalle1
        \\ dsb ish
        \\ isb
        ::: .{ .memory = true });
}
