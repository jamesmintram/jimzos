//! AArch64 kernel virtual-memory layout shared across MMU consumers.

const std = @import("std");

pub const kernel_direct_map_base: u64 = 0xffff000000000000;

pub inline fn physicalToVirtual(physical_address: u64) !usize {
    const virtual_address = std.math.add(
        u64,
        kernel_direct_map_base,
        physical_address,
    ) catch return error.PhysicalAddressOverflow;
    if (virtual_address > std.math.maxInt(usize)) return error.PhysicalAddressOverflow;
    return @intCast(virtual_address);
}

pub inline fn virtualToPhysical(virtual_address: usize) !u64 {
    if (virtual_address < kernel_direct_map_base) return error.NotKernelDirectMapAddress;
    return @intCast(virtual_address - kernel_direct_map_base);
}

test "direct-map address conversion round trips" {
    const physical: u64 = 0x4012_3000;
    const virtual = try physicalToVirtual(physical);
    try std.testing.expectEqual(physical, try virtualToPhysical(virtual));
}
