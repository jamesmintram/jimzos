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

pub fn BumpAllocator() type {
    return struct {

        addr: usize,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .addr = 0xffff000002000000
            };
        }

        pub fn allocator(self: *Self) Allocator {
            return Allocator.init(self, alloc, resize, free);
        }

        fn alloc(
            self: *Self,
            n: usize,
            ptr_align: u29,
            len_align: u29,
            ra: usize,
        ) error{OutOfMemory}![]u8 {
            _ = ra;
            _ = ptr_align;

            assert(n > 0);
            const aligned_len = mem.alignForward(n, mem.page_size);
    
            var alloc_addr = self.addr;
            self.addr += aligned_len;

            const return_ptr = @ptrCast([*]u8,@intToPtr(*u8, alloc_addr));
            return return_ptr[0..alignPageAllocLen(aligned_len, n, len_align)];   
        }

        fn resize(
            self: *Self,
            buf_unaligned: []u8,
            buf_align: u29,
            new_len: usize,
            len_align: u29,
            return_address: usize,
        ) ?usize {
            _ = self;
            _ = buf_unaligned;
            _ = buf_align;
            _ = new_len;
            _ = len_align;
            _ = return_address;

            return null;
        }

        fn free(
            self: *Self,
            buf: []u8,
            buf_align: u29,
            ra: usize,
        ) void {
            _ = self;
            _ = buf;
            _ = buf_align;
            _ = ra;   
        }
    };
}
