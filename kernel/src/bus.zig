//! Parent-provided resources and the active handles retained by drivers.
//!
//! Addresses in an `AddressRange` belong to the accompanying `MemorySpace`.
//! Only the root CPU space interprets them as CPU-physical addresses. Child
//! buses can translate a range and delegate it to their parent without exposing
//! that translation to device drivers.

const std = @import("std");
const mmu = @import("arch/mmu.zig");
const phys = @import("phys_range");
const PhysRange = phys.PhysRange;
const MmioRegion = @import("io/mmio_region.zig").MmioRegion;

pub const AddressRange = struct {
    start: u64,
    byte_len: u64,

    pub fn init(start: u64, byte_len: u64) !AddressRange {
        _ = try PhysRange.fromStartSize(start, byte_len);
        return .{ .start = start, .byte_len = byte_len };
    }

    pub fn end(self: AddressRange) u64 {
        return self.start + self.byte_len;
    }
};

pub const MemorySpace = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        map: *const fn (*anyopaque, AddressRange) anyerror!MmioRegion,
    };

    pub fn map(self: MemorySpace, range: AddressRange) !MmioRegion {
        return self.vtable.map(self.context, range);
    }
};

pub const MemoryResource = struct {
    space: MemorySpace,
    range: AddressRange,

    pub fn map(self: MemoryResource) !MmioRegion {
        return self.space.map(self.range);
    }
};

/// The address-space capability inherited from a device's parent bus.
pub const Bus = struct {
    memory: MemorySpace,

    pub fn mmio(self: Bus, address: u64, byte_len: u64) !MemoryResource {
        return .{
            .space = self.memory,
            .range = try AddressRange.init(address, byte_len),
        };
    }
};

var cpu_space_context: u8 = 0;

/// Root bus used after the final kernel translation map is installed.
pub fn cpuBus() Bus {
    return .{
        .memory = .{
            .context = &cpu_space_context,
            .vtable = &.{ .map = mapCpuPhysical },
        },
    };
}

fn mapCpuPhysical(_: *anyopaque, range: AddressRange) !MmioRegion {
    const region = try regionForCpuPhysical(range);
    const physical = try PhysRange.fromStartSize(range.start, range.byte_len);
    const physical_pages = try physical.alignedOutward(phys.page_size);
    const virtual_page_start = try mmu.physicalToVirtual(physical_pages.start);
    try mmu.mapRange(
        virtual_page_start,
        physical_pages,
        .{
            .memory_type = .device,
            .writable = true,
            .executable = false,
        },
    );
    return region;
}

fn regionForCpuPhysical(range: AddressRange) !MmioRegion {
    const physical_base = std.math.cast(usize, range.start) orelse
        return error.MmioResourceAddressOverflow;
    const byte_len = std.math.cast(usize, range.byte_len) orelse
        return error.MmioResourceSizeOverflow;
    return MmioRegion.init(
        physical_base,
        try mmu.physicalToVirtual(range.start),
        byte_len,
    );
}

test "bus address ranges reject empty and overflowing resources" {
    const range = try AddressRange.init(0x1003, 0x2ffe);
    try std.testing.expectEqual(@as(u64, 0x4001), range.end());
    try std.testing.expectError(error.EmptyRange, AddressRange.init(0x1000, 0));
    try std.testing.expectError(
        error.RangeOverflow,
        AddressRange.init(std.math.maxInt(u64), 2),
    );
}
