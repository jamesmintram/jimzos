const boot = @import("../../boot/boot_info.zig");
const phys = @import("phys_range");

const kernel_va_base: u64 = 0xffff000000000000;
const table_size: u64 = 4096;
const entries_per_table = 512;
const table_address_mask: u64 = 0x0000fffffffff000;
const descriptor_table_or_page: u64 = 3;
const access_flag: u64 = 1 << 10;
const inner_shareable: u64 = 3 << 8;
const normal_flags: u64 = access_flag | inner_shareable;

extern const __page_tables_phys_start: u8;
extern const __page_tables_phys_end: u8;
var tail_next: u64 = 0;

pub fn mapAllocatorMetadata(info: *const boot.BootInfo) !void {
    try mapTemporaryNormal(info.allocator_metadata);
}

pub fn mapTemporaryNormal(range: phys.PhysRange) !void {
    const pool_start: u64 = @intFromPtr(&__page_tables_phys_start);
    const pool_end: u64 = @intFromPtr(&__page_tables_phys_end);
    if (tail_next == 0) tail_next = pool_start + (pool_end - pool_start) / 2;
    var arena = TailArena{
        .next = tail_next,
        .end = pool_end,
    };

    var cursor = range.start;
    while (cursor < range.end) : (cursor += phys.page_size) {
        try mapPage(pool_start, kernel_va_base + cursor, cursor, normal_flags, &arena);
    }
    tail_next = arena.next;
    flushTranslations();
}

const TailArena = struct {
    next: u64,
    end: u64,

    fn allocate(self: *TailArena) !u64 {
        if (self.next + table_size > self.end) return error.BootstrapPageTablesExhausted;
        const result = self.next;
        self.next += table_size;
        @memset(tableFromPhysical(result), 0);
        return result;
    }
};

fn mapPage(root: u64, virtual: u64, physical: u64, flags: u64, arena: *TailArena) !void {
    const l1 = try ensureNext(root, indexFor(virtual, 39), arena);
    const l2 = try ensureNext(l1, indexFor(virtual, 30), arena);
    const l3 = try ensureNext(l2, indexFor(virtual, 21), arena);
    tableFromPhysical(l3)[indexFor(virtual, 12)] = physical | flags | descriptor_table_or_page;
}

fn ensureNext(parent_phys: u64, index: usize, arena: *TailArena) !u64 {
    const parent = tableFromPhysical(parent_phys);
    const entry = parent[index];
    if (entry != 0) {
        if (entry & descriptor_table_or_page != descriptor_table_or_page) return error.ExpectedBootstrapTable;
        return entry & table_address_mask;
    }
    const child = try arena.allocate();
    parent[index] = child | descriptor_table_or_page;
    return child;
}

fn indexFor(virtual: u64, shift: u6) usize {
    return @intCast((virtual >> shift) & (entries_per_table - 1));
}

fn tableFromPhysical(physical_address: u64) *[entries_per_table]u64 {
    return @ptrFromInt(@as(usize, @intCast(kernel_va_base + physical_address)));
}

fn flushTranslations() void {
    asm volatile (
        \\ dsb ishst
        \\ tlbi vmalle1
        \\ dsb ish
        \\ isb
        ::: .{ .memory = true });
}
