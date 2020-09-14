// const builtin = @import("builtin");
const io = @import("io.zig");
const vga = @import("vga.zig");
const uart = io.uart;
const util = @import("util.zig");
const framebuffer = vga.framebuffer;
const std = @import("std");

const debug = std.debug;
const assert = debug.assert;

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

const ProcessManager = struct {

};

pub fn create_process (allocator : *Allocator) !*Process
{
    var newProcess = try allocator.create(Process);
    newProcess.next = undefined;
    newProcess.prev = undefined;
    
    newProcess.pid = 1;

    return newProcess;
}

const Process = struct {
    next : ?*Process,
    prev : ?*Process,

    pid : u32,

    thread_list : ?*Thread,
    address_sapce : ?*AddressSpace,
};

const AddressSpace = struct {

};

pub fn create_default_address_space(allocator : *Allocator) *AddressSpace {
    return undefined;
}

const CPUFrame = packed struct {
    tf_sp:      u64,       //0
    tf_lr:      u64,       //8
    tf_elr:     u64,       //16
    tf_spsr:    u32,       //24
    tf_esr:     u32,       //28
    tf_x:       [30]u64,   //32    
};

const Thread = struct {
    next : ?*Thread,
    prev : ?*Thread,

    proc : *Process,

    tid : u32,

    // Alignment better done some other way?
    kernel_stack : [4096]u8 align(16),
    
    // Kernel Stack PTR
    stack_pointer : usize,
};

//TODO: Possible to set some consts that are = to the OffsetOf(...)
// export const TF_SP : usize = @OffsetOf(Thread, "stack_pointer");

export const TB_SP : usize = 0;

pub fn create_default_thread(allocator : *Allocator, parent : *Process) !*Thread {
    var newThread = try allocator.create(Thread);

    newThread.tid = 2;
    newThread.proc = parent;

    newThread.next = undefined;
    newThread.prev = undefined;

    return newThread;
}

pub fn create_initial_thread(allocator : *Allocator) !*Thread {
    var kernel_proc = create_process(allocator) catch unreachable;

    var newThread = try allocator.create(Thread);
    newThread.tid = 1;
    newThread.proc = kernel_proc;

    newThread.next = undefined;
    newThread.prev = undefined;

    // Stack should start from the END of the array
    newThread.stack_pointer = @ptrToInt(&newThread.kernel_stack[newThread.kernel_stack.len -1]) - @sizeOf(CPUFrame);
    
    var frame = @intToPtr(*CPUFrame, newThread.stack_pointer);
    
    frame.tf_elr = 0;
    frame.tf_lr = @ptrToInt(kmain_init);
    frame.tf_sp = newThread.stack_pointer;

    var spsr : u32 = 0;
    spsr |= 1 << 0;     // Dunno what this does..
    spsr |= 1 << 2;     // .M[3:2] = 0b100 -->  Return to EL1
    spsr |= 1 << 6;     // FIQ masked
    spsr |= 1 << 7;     // IRQ masked
    spsr |= 1 << 8;     // SError (System Error) masked
    spsr |= 1 << 9;

    frame.tf_spsr = spsr;

    return newThread;
}

pub fn current_thread() *Thread {
    //Read this from the CPU register
}

//TODO: _ctx_switch_to_initial
extern fn _ctx_switch_to_initial(sp : usize) void;

pub fn thread_switch(thread : *Thread) void {
    // Switch to new user space proc address space
    // Call the platform code for switch_to_thread
    // - Update the current ThreadID register value
    // - Restore registers + ERET to same level

    uart.write("Switching to process {} thread {}\n", .{thread.proc.pid, thread.tid});
    _ctx_switch_to_initial(thread.stack_pointer);
}

pub fn map_range(as : *AddressSpace) void {
    //Split, merge etc
}
pub fn unmap_range(as : *AddressSpace) void {
    //Split, merge etc
}

pub fn update_page_table(as : AddressSpace) void {
    //TODO Pass in a pointer? or something to output to
}

export fn kmain() noreturn {
    uart.init();
    uart.write("JimZOS v{}\r", .{util.Version});

    // Get inside a thread context ASAP
    var init_thread = create_initial_thread(&page_allocator.allocator) catch unreachable;
    thread_switch(init_thread);

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