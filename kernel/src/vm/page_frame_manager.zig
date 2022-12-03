const mem = @import("std").mem;
const Allocator = mem.Allocator;

const assert = @import("std").debug.assert;

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
                .free = free,
            },
        };
    }

    pub fn alloc(
        ctx: *anyopaque,
        n: usize,
        log2_ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

        _ = ret_addr;
        _ = log2_ptr_align;

        assert(n > 0);
        const aligned_len = mem.alignForward(n, mem.page_size);

        // Take a copy of our current address before we bump it
        var alloc_addr = self.addr;
        self.addr += aligned_len;

        const return_ptr = @ptrCast([*]u8, @intToPtr(*u8, alloc_addr));
        return return_ptr;
    }

    pub fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

        _ = self;
        _ = buf;
        _ = log2_buf_align;
        _ = new_len;
        _ = ret_addr;

        return false;
    }

    pub fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        ret_addr: usize,
    ) void {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

        _ = self;
        _ = buf;
        _ = log2_buf_align;
        _ = ret_addr;
    }
};
