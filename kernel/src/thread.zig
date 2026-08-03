const process = @import("proc.zig");
const cpu = @import("arch/cpu.zig").cpu;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CPUFrame = @import("arch/aarch64/types/cpu_frame.zig").CPUFrame;

pub const Thread = extern struct {
    next: ?*Thread,
    prev: ?*Thread,

    proc: *process.Process,

    tid: u32,

    // Kernel Stack PTR
    stack_pointer: usize,

    // Alignment better done some other way?
    kernel_stack: [4096]u8 align(16),
};

pub fn create_default_thread(allocator: *Allocator, parent: *process.Process) !*Thread {
    const newThread = try allocator.create(Thread);

    newThread.tid = 2;
    newThread.proc = parent;

    newThread.next = undefined;
    newThread.prev = undefined;

    return newThread;
}

var thread_list: *Thread = undefined;

fn add_to_thread_list(new_thread: *Thread) void {
    new_thread.next = thread_list;
    new_thread.prev = undefined;

    thread_list = new_thread;
}

pub fn create_initial_thread(allocator: *Allocator, thread_fn: *const fn () void) !*Thread {
    const kernel_proc = process.createProcess(allocator) catch unreachable;

    const newThread = try allocator.create(Thread);
    newThread.tid = 1;
    newThread.proc = kernel_proc;

    newThread.next = undefined;
    newThread.prev = undefined;

    const stack_top = @intFromPtr(&newThread.kernel_stack) + newThread.kernel_stack.len;
    newThread.stack_pointer = stack_top - @sizeOf(CPUFrame);

    const frame: *CPUFrame = @ptrFromInt(newThread.stack_pointer);
    frame.* = std.mem.zeroes(CPUFrame);

    frame.tf_lr = @intFromPtr(&threadEntry);
    frame.tf_x[0] = @intFromPtr(thread_fn);
    frame.tf_sp = newThread.stack_pointer;

    var spsr: u32 = 0;
    spsr |= 1 << 0; // Dunno what this does..
    spsr |= 1 << 2; // .M[3:2] = 0b100 -->  Return to EL1
    spsr |= 1 << 6; // FIQ masked
    spsr |= 1 << 7; // IRQ masked
    spsr |= 1 << 8; // SError (System Error) masked
    spsr |= 1 << 9;

    frame.tf_spsr = spsr;

    add_to_thread_list(newThread);

    return newThread;
}

fn threadEntry(entry_address: usize) callconv(.c) noreturn {
    const entry: *const fn () void = @ptrFromInt(entry_address);
    entry();
    @panic("kernel thread returned");
}

pub fn current_thread() *Thread {
    return @ptrFromInt(cpu.currentThreadPointer());
}

pub fn yield() void {
    //NAIVE ROUND ROBIN
    const current = current_thread();
    const next = current.next orelse thread_list;

    switch_to(next);
}

extern fn _ctx_switch_to_initial(sp: usize) void;
pub fn switch_to_initial(thread: *Thread) void {
    _ctx_switch_to_initial(@intFromPtr(thread));
}

extern fn _ctx_switch_to(old_thread: usize, new_thread: usize) void;
pub fn switch_to(thread: *Thread) void {
    // Switch to new user space proc address space
    // Call the platform code for switch_to_thread
    // - Update the current ThreadID register value
    // - Restore registers + ERET to same level

    const current = current_thread();

    //TODO: Check they are not the same, otherwise we just instant return

    if (current != thread) {
        _ctx_switch_to(@intFromPtr(current), @intFromPtr(thread));
    }

    // uart.write("Switching to process {} thread {}\n", .{thread.proc.pid, thread.tid});

}
