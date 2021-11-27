const std = @import("std");
const Allocator = std.mem.Allocator;

const thread = @import("thread.zig");
const address_space = @import("vm/address_space.zig");

pub const Process = struct {
    next: ?*Process,
    prev: ?*Process,

    pid: u32,

    thread_list: ?*thread.Thread,
    address_sapce: ?*address_space.AddressSpace,
};

pub fn createProcess(allocator: *Allocator) !*Process {
    var newProcess = try allocator.create(Process);
    newProcess.next = undefined;
    newProcess.prev = undefined;

    newProcess.pid = 1;

    return newProcess;
}
