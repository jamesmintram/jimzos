const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = mem.Alignment;

const assert = std.debug.assert;

// `std.mem.page_size` was removed; this kernel uses a fixed 4 KiB page.
const page_size = 4096;

extern const __heap_start: usize;
extern const __heap_phys_start: *usize;

pub const BumpAllocator = struct {
    addr: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{ .addr = 0xffff000002000000 };
    }

    pub fn allocator(self: *BumpAllocator) Allocator {
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

    pub fn alloc(
        ctx: *anyopaque,
        n: usize,
        alignment: Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        _ = ret_addr;
        _ = alignment;

        assert(n > 0);
        const aligned_len = mem.alignForward(usize, n, page_size);

        // Take a copy of our current address before we bump it
        const alloc_addr = self.addr;
        self.addr += aligned_len;

        const return_ptr: [*]u8 = @ptrFromInt(alloc_addr);
        return return_ptr;
    }

    pub fn resize(
        ctx: *anyopaque,
        buf: []u8,
        alignment: Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        _ = self;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;

        return false;
    }

    pub fn remap(
        ctx: *anyopaque,
        buf: []u8,
        alignment: Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        _ = self;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;

        return null;
    }

    pub fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: Alignment,
        ret_addr: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        _ = self;
        _ = buf;
        _ = alignment;
        _ = ret_addr;
    }
};
