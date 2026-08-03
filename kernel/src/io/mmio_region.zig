const std = @import("std");
const cpu = @import("../arch/cpu.zig").cpu;

/// A bounded MMIO range and the virtual address through which the kernel
/// currently accesses it. A bus owns translation and mapping; drivers retain
/// this value and perform bounded volatile register accesses through it.
pub const MmioRegion = struct {
    physical_base: usize,
    virtual_base: usize,
    byte_len: usize,

    pub fn init(physical_base: usize, virtual_base: usize, byte_len: usize) !MmioRegion {
        if (byte_len == 0) return error.EmptyMmioRegion;
        const last_byte = byte_len - 1;
        if (physical_base > std.math.maxInt(usize) - last_byte or
            virtual_base > std.math.maxInt(usize) - last_byte)
        {
            return error.MmioRegionOverflow;
        }
        return .{
            .physical_base = physical_base,
            .virtual_base = virtual_base,
            .byte_len = byte_len,
        };
    }

    /// Construct a region for bootstrap mappings where VA == PA.
    pub fn identityMapped(physical_base: usize, byte_len: usize) !MmioRegion {
        return init(physical_base, physical_base, byte_len);
    }

    /// Preserve the claimed physical range while replacing its active mapping.
    pub fn withVirtualBase(self: MmioRegion, virtual_base: usize) !MmioRegion {
        return init(self.physical_base, virtual_base, self.byte_len);
    }

    /// Return a bounded view into this mapping without creating a second
    /// mapping or allowing the caller to reconstruct one from raw addresses.
    pub fn subregion(self: MmioRegion, offset: usize, byte_len: usize) !MmioRegion {
        if (byte_len == 0) return error.EmptyMmioRegion;
        if (offset > self.byte_len or byte_len > self.byte_len - offset) {
            return error.MmioSubregionOutOfBounds;
        }
        return init(
            self.physical_base + offset,
            self.virtual_base + offset,
            byte_len,
        );
    }

    pub fn physicalBase(self: MmioRegion) usize {
        return self.physical_base;
    }

    pub fn virtualBase(self: MmioRegion) usize {
        return self.virtual_base;
    }

    pub fn size(self: MmioRegion) usize {
        return self.byte_len;
    }

    pub fn samePhysicalRange(self: MmioRegion, other: MmioRegion) bool {
        return self.physical_base == other.physical_base and self.byte_len == other.byte_len;
    }

    pub fn read32(self: MmioRegion, offset: usize) u32 {
        const address = self.accessAddress(offset, @sizeOf(u32), @alignOf(u32));
        cpu.dataMemoryBarrier();
        return @as(*volatile u32, @ptrFromInt(address)).*;
    }

    pub fn write32(self: MmioRegion, offset: usize, value: u32) void {
        const address = self.accessAddress(offset, @sizeOf(u32), @alignOf(u32));
        cpu.dataMemoryBarrier();
        @as(*volatile u32, @ptrFromInt(address)).* = value;
    }

    pub fn read64(self: MmioRegion, offset: usize) u64 {
        const address = self.accessAddress(offset, @sizeOf(u64), @alignOf(u64));
        cpu.dataMemoryBarrier();
        return @as(*volatile u64, @ptrFromInt(address)).*;
    }

    fn accessAddress(self: MmioRegion, offset: usize, width: usize, alignment: usize) usize {
        std.debug.assert(offset % alignment == 0);
        std.debug.assert(width <= self.byte_len);
        std.debug.assert(offset <= self.byte_len - width);
        return self.virtual_base + offset;
    }
};

test "MMIO region preserves physical identity when rebased" {
    const identity = try MmioRegion.identityMapped(0x1000, 0x200);
    const mapped = try identity.withVirtualBase(0xffff000000001000);

    try std.testing.expect(identity.samePhysicalRange(mapped));
    try std.testing.expectEqual(@as(usize, 0x1000), mapped.physicalBase());
    try std.testing.expectEqual(@as(usize, 0xffff000000001000), mapped.virtualBase());
    try std.testing.expectEqual(@as(usize, 0x200), mapped.size());
}

test "MMIO region rejects empty and overflowing ranges" {
    try std.testing.expectError(error.EmptyMmioRegion, MmioRegion.identityMapped(0x1000, 0));
    try std.testing.expectError(
        error.MmioRegionOverflow,
        MmioRegion.init(std.math.maxInt(usize), 0x1000, 2),
    );
}

test "MMIO subregions remain bounded by their parent" {
    const parent = try MmioRegion.init(0x1000, 0xffff000000001000, 0x400);
    const child = try parent.subregion(0x100, 0x200);

    try std.testing.expectEqual(@as(usize, 0x1100), child.physicalBase());
    try std.testing.expectEqual(@as(usize, 0xffff000000001100), child.virtualBase());
    try std.testing.expectEqual(@as(usize, 0x200), child.size());
    try std.testing.expectError(error.EmptyMmioRegion, parent.subregion(0, 0));
    try std.testing.expectError(error.MmioSubregionOutOfBounds, parent.subregion(0x300, 0x200));
}
