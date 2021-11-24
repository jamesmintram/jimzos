const mem = @import("std").mem;
const Allocator = mem.Allocator;

const assert = @import("std").debug.assert;

extern const __heap_start: usize;
extern const __heap_phys_start: *usize;

fn alignPageAllocLen(full_len: usize, len: usize, len_align: u29) usize {
    const aligned_len = mem.alignAllocLen(full_len, len, len_align);
    assert(mem.alignForward(aligned_len, mem.page_size) == full_len);
    return aligned_len;
}

pub const BumpAllocator = struct {
    const Self = @This();

    addr: usize,
    allocator: Allocator,

    pub fn alloc(allocator: *Allocator, n: usize, alignment: u29, len_align: u29, ra: usize) error{OutOfMemory}![]u8 {
        _ = ra;
        _ = alignment;

        assert(n > 0);
        const aligned_len = mem.alignForward(n, mem.page_size);
        const self = @fieldParentPtr(Self, "allocator", allocator);

        var return_address = self.addr;
        self.addr += aligned_len;

        return @ptrCast([*]u8, @intToPtr(*u8, return_address))[0..alignPageAllocLen(aligned_len, n, len_align)];
    }

    pub fn resize(
        allocator: *Allocator,
        buf_unaligned: []u8,
        buf_align: u29,
        new_size: usize,
        len_align: u29,
        return_address: usize,
    ) Allocator.Error!usize {
        _ = allocator;
        _ = buf_unaligned;
        _ = buf_align;
        _ = new_size;
        _ = len_align;
        _ = return_address;

        //const self = @fieldParentPtr(Self, "allocator", allocator);
        //const new_size_aligned = mem.alignForward(new_size, mem.page_size);

        //FIXME  std/heap.zig:234 (BumpAllocator)
        return error.OutOfMemory;
    }
};

pub fn create() BumpAllocator {
    return BumpAllocator{
        // .addr = 0xffff00000038d000, //__heap_start,
        .addr = 0xffff00000F38d000, //__heap_start + LOADS,
        .allocator = Allocator{
            .allocFn = BumpAllocator.alloc,
            .resizeFn = BumpAllocator.resize,
        },
    };
}
