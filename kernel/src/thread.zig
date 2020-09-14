const process = @import("proc.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CPUFrame = packed struct {
    tf_sp:      u64,       //0
    tf_lr:      u64,       //8
    tf_elr:     u64,       //16
    tf_spsr:    u32,       //24
    tf_esr:     u32,       //28
    tf_x:       [30]u64,   //32    
};

pub const Thread = struct {
    next : ?*Thread,
    prev : ?*Thread,

    proc : *process.Process,

    tid : u32,

    // Kernel Stack PTR
    stack_pointer : usize,

    // Alignment better done some other way?
    kernel_stack : [4096]u8 align(16),
};


pub fn create_default_thread(allocator : *Allocator, parent : *process.Process) !*Thread {
    var newThread = try allocator.create(Thread);

    newThread.tid = 2;
    newThread.proc = parent;

    newThread.next = undefined;
    newThread.prev = undefined;

    return newThread;
}

pub fn create_initial_thread(allocator : *Allocator, thread_fn : fn () void) !*Thread {
    var kernel_proc = process.create_process(allocator) catch unreachable;

    var newThread = try allocator.create(Thread);
    newThread.tid = 1;
    newThread.proc = kernel_proc;

    newThread.next = undefined;
    newThread.prev = undefined;

    // Stack should start from the END of the array
    newThread.stack_pointer = @ptrToInt(&newThread.kernel_stack[newThread.kernel_stack.len -1]) - @sizeOf(CPUFrame);
    
    var frame = @intToPtr(*CPUFrame, newThread.stack_pointer);
    
    frame.tf_elr = 0;
    frame.tf_lr = @ptrToInt(thread_fn);
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

    // uart.write("Switching to process {} thread {}\n", .{thread.proc.pid, thread.tid});
    _ctx_switch_to_initial(@ptrToInt(thread));
}