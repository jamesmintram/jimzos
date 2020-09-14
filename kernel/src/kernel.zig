// const builtin = @import("builtin");
const io = @import("io.zig");
const vga = @import("vga.zig");
const uart = io.uart;
const util = @import("util.zig");
const framebuffer = vga.framebuffer;
const std = @import("std");

const debug = std.debug;
const assert = debug.assert;

const process = @import("process.zig");
const thread = @import("thread.zig");

const mem = std.mem;
const Allocator = mem.Allocator;

// const emmc = io.emmc;

// Alloc/Free to work?
// Process ping pong
/// Verifies that the adjusted length will still map to the full length
pub fn alignPageAllocLen(full_len: usize, len: usize, len_align: u29) usize {
    const aligned_len = mem.alignAllocLen(full_len, len, len_align);
    assert(mem.alignForward(aligned_len, mem.page_size) == full_len);
    return aligned_len;
}

extern const __heap_start : usize;

const BumpAllocator = struct {
    const Self = @This();
    
    addr : usize,
    allocator: Allocator,

    fn alloc(allocator: *Allocator, n: usize, alignment: u29, len_align: u29, ra: usize) error{OutOfMemory}![]u8 {
        assert(n > 0);
        const aligned_len = mem.alignForward(n, mem.page_size);
        const self = @fieldParentPtr(Self, "allocator", allocator);
        
        var return_address = self.addr;
        self.addr += aligned_len;

        return @ptrCast([*]u8, @intToPtr(*u8, return_address))[0..alignPageAllocLen(aligned_len, n, len_align)];
    }

    fn resize(
        allocator: *Allocator,
        buf_unaligned: []u8,
        buf_align: u29,
        new_size: usize,
        len_align: u29,
        return_address: usize,
    ) Allocator.Error!usize {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        const new_size_aligned = mem.alignForward(new_size, mem.page_size);

        //FIXME  std/heap.zig:234 (BumpAllocator)
        return error.OutOfMemory;
    }
};

var page_allocator = BumpAllocator{
    // .addr = 0xffff00000038d000, //__heap_start,
    .addr = 0xffff00000F38d000, //__heap_start + LOADS,
    .allocator = Allocator {
        .allocFn = BumpAllocator.alloc,
        .resizeFn = BumpAllocator.resize,
    }
};


//TODO: Possible to set some consts that are = to the OffsetOf(...)
// export const TF_SP : usize = @OffsetOf(Thread, "stack_pointer");



export fn kmain() noreturn {
    uart.init();
    uart.write("JimZOS v{}\r", .{util.Version});

    // Get inside a thread context ASAP
    var init_thread = thread.create_initial_thread(&page_allocator.allocator, kmain_init) catch unreachable;
    thread.thread_switch(init_thread);

    uart.write("End of kmain\r", .{});
    unreachable;
}

fn kmain_init() noreturn {
    // framebuffer.init().?;  
    // framebuffer.write("JimZOS v{}\r", .{util.Version});

    uart.write("Entered init thread\r", .{});

    // 

    while (true) {
        const x = uart.get();
        uart.put(x);
        framebuffer.put(x);
    }
}