const std = @import("std");
const Allocator = std.mem.Allocator;

const thread = @import("thread.zig");
const address_space = @import("vm/address_space.zig");

pub const Process = struct {
    next: ?*Process,
    prev: ?*Process,

    pid: u32,

    thread_list: ?*thread.Thread,
    address_space: ?*address_space.AddressSpace,
};

pub fn createProcess(allocator: *Allocator) !*Process {
    const process = try allocator.create(Process);
    process.* = .{
        .next = null,
        .prev = null,
        .pid = 1,
        .thread_list = null,
        .address_space = null,
    };
    return process;
}
