const std = @import("std");
const boot = @import("../boot/boot_info.zig");
const ranges = @import("phys_range");

pub const page_size: usize = @intCast(ranges.page_size);
const kernel_va_base: usize = 0xffff000000000000;

const Bank = struct {
    range: ranges.PhysRange,
    page_count: usize,
    bitmap_offset: usize,
};

pub const Stats = struct {
    total_pages: usize,
    usable_pages: usize,
    allocated_pages: usize,
    free_pages: usize,
};

pub const PhysicalAllocator = struct {
    banks: [boot.max_memory_ranges]Bank = undefined,
    bank_count: usize = 0,
    bitmap: []u8 = &.{},
    info: *const boot.BootInfo = undefined,
    total_pages: usize = 0,
    usable_pages: usize = 0,
    allocated_pages: usize = 0,

    const Self = @This();

    pub fn requiredMetadataBytes(memory: *const boot.MemoryList) !u64 {
        var bytes: u64 = 0;
        for (memory.constSlice()) |bank| {
            const pages = bank.size() / ranges.page_size;
            const bank_bytes = (pages + 7) / 8;
            if (bank_bytes > std.math.maxInt(u64) - bytes) return error.AllocatorMetadataOverflow;
            bytes += bank_bytes;
        }
        if (bytes == 0) return error.NoMemoryForAllocator;
        return ranges.alignUp(bytes, ranges.page_size);
    }

    pub fn init(self: *Self, info: *const boot.BootInfo) !void {
        self.* = .{};
        self.info = info;

        const metadata_size: usize = @intCast(info.allocator_metadata.size());
        const metadata_va = try physicalToVirtual(info.allocator_metadata.start);
        const metadata_ptr: [*]u8 = @ptrFromInt(metadata_va);
        self.bitmap = metadata_ptr[0..metadata_size];
        @memset(self.bitmap, 0xff);

        var bitmap_offset: usize = 0;
        for (info.memory.constSlice()) |memory| {
            const page_count: usize = @intCast(memory.size() / ranges.page_size);
            const bitmap_bytes = (page_count + 7) / 8;
            if (bitmap_offset + bitmap_bytes > self.bitmap.len) return error.AllocatorMetadataTooSmall;
            self.banks[self.bank_count] = .{
                .range = memory,
                .page_count = page_count,
                .bitmap_offset = bitmap_offset,
            };
            self.bank_count += 1;
            self.total_pages += page_count;
            bitmap_offset += bitmap_bytes;
        }

        for (info.usable.constSlice()) |usable| {
            var phys = usable.start;
            while (phys < usable.end) : (phys += ranges.page_size) {
                const location = self.locatePage(phys) orelse return error.UsablePageOutsideMemory;
                self.setUsed(location.bank, location.page, false);
                self.usable_pages += 1;
            }
        }
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn allocatePages(self: *Self, count: usize) ?u64 {
        if (count == 0 or count > self.usable_pages - self.allocated_pages) return null;

        for (self.banks[0..self.bank_count], 0..) |bank, bank_index| {
            var run_start: usize = 0;
            var run_length: usize = 0;
            for (0..bank.page_count) |page_index| {
                if (!self.isUsed(bank_index, page_index)) {
                    if (run_length == 0) run_start = page_index;
                    run_length += 1;
                    if (run_length == count) {
                        for (run_start..run_start + count) |page| self.setUsed(bank_index, page, true);
                        self.allocated_pages += count;
                        return bank.range.start + @as(u64, @intCast(run_start)) * ranges.page_size;
                    }
                } else {
                    run_length = 0;
                }
            }
        }
        return null;
    }

    pub fn releasePages(self: *Self, physical_address: u64, count: usize) !void {
        if (count == 0 or physical_address % ranges.page_size != 0) return error.InvalidPageRange;
        const size = std.math.mul(u64, count, ranges.page_size) catch return error.InvalidPageRange;
        const released = ranges.PhysRange.fromStartSize(physical_address, size) catch return error.InvalidPageRange;
        if (!isUsableRange(self.info, released)) return error.PageRangeNotAllocatable;

        const location = self.locatePage(physical_address) orelse return error.InvalidPageRange;
        const bank = self.banks[location.bank];
        if (location.page + count > bank.page_count) return error.PageRangeCrossesBank;
        for (location.page..location.page + count) |page| {
            if (!self.isUsed(location.bank, page)) return error.DoubleFree;
        }
        for (location.page..location.page + count) |page| self.setUsed(location.bank, page, false);
        self.allocated_pages -= count;
    }

    pub fn stats(self: *const Self) Stats {
        return .{
            .total_pages = self.total_pages,
            .usable_pages = self.usable_pages,
            .allocated_pages = self.allocated_pages,
            .free_pages = self.usable_pages - self.allocated_pages,
        };
    }

    const Location = struct { bank: usize, page: usize };

    fn locatePage(self: *const Self, physical_address: u64) ?Location {
        for (self.banks[0..self.bank_count], 0..) |bank, bank_index| {
            if (physical_address >= bank.range.start and physical_address < bank.range.end) {
                return .{
                    .bank = bank_index,
                    .page = @intCast((physical_address - bank.range.start) / ranges.page_size),
                };
            }
        }
        return null;
    }

    fn isUsed(self: *const Self, bank_index: usize, page_index: usize) bool {
        const bank = self.banks[bank_index];
        const byte_index = bank.bitmap_offset + page_index / 8;
        const mask: u8 = @as(u8, 1) << @intCast(page_index % 8);
        return self.bitmap[byte_index] & mask != 0;
    }

    fn setUsed(self: *Self, bank_index: usize, page_index: usize, used: bool) void {
        const bank = self.banks[bank_index];
        const byte_index = bank.bitmap_offset + page_index / 8;
        const mask: u8 = @as(u8, 1) << @intCast(page_index % 8);
        if (used) {
            self.bitmap[byte_index] |= mask;
        } else {
            self.bitmap[byte_index] &= ~mask;
        }
    }

    fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        if (n == 0 or alignment.toByteUnits() > page_size) return null;
        const page_count = std.math.divCeil(usize, n, page_size) catch return null;
        const self: *Self = @ptrCast(@alignCast(ctx));
        const physical_address = self.allocatePages(page_count) orelse return null;
        return @ptrFromInt(physicalToVirtual(physical_address) catch return null);
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;
        const old_pages = std.math.divCeil(usize, buf.len, page_size) catch return false;
        const new_pages = std.math.divCeil(usize, new_len, page_size) catch return false;
        return old_pages == new_pages;
    }

    fn remap(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        _ = alignment;
        _ = ret_addr;
        if (buf.len == 0) return;
        const address = @intFromPtr(buf.ptr);
        if (address < kernel_va_base) @panic("free of non-kernel address");
        const page_count = std.math.divCeil(usize, buf.len, page_size) catch @panic("invalid allocation size");
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.releasePages(address - kernel_va_base, page_count) catch @panic("invalid physical page free");
    }
};

fn physicalToVirtual(physical_address: u64) !usize {
    if (physical_address > std.math.maxInt(usize) - kernel_va_base) return error.PhysicalAddressOverflow;
    return @intCast(physical_address + kernel_va_base);
}

fn isUsableRange(info: *const boot.BootInfo, candidate: ranges.PhysRange) bool {
    for (info.usable.constSlice()) |usable| {
        if (usable.contains(candidate)) return true;
    }
    return false;
}
