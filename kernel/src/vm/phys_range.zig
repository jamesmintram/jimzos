const std = @import("std");

pub const page_size: u64 = 4096;

pub const PhysRange = struct {
    start: u64,
    end: u64,

    pub fn fromStartSize(start: u64, byte_count: u64) !PhysRange {
        if (byte_count == 0) return error.EmptyRange;
        if (byte_count > std.math.maxInt(u64) - start) return error.RangeOverflow;
        return .{ .start = start, .end = start + byte_count };
    }

    pub fn size(self: PhysRange) u64 {
        return self.end - self.start;
    }

    pub fn contains(self: PhysRange, other: PhysRange) bool {
        return self.start <= other.start and other.end <= self.end;
    }

    pub fn overlaps(self: PhysRange, other: PhysRange) bool {
        return self.start < other.end and other.start < self.end;
    }

    pub fn alignedInward(self: PhysRange, alignment: u64) !?PhysRange {
        const start = try alignUp(self.start, alignment);
        const end = alignDown(self.end, alignment);
        if (start >= end) return null;
        return .{ .start = start, .end = end };
    }

    pub fn alignedOutward(self: PhysRange, alignment: u64) !PhysRange {
        const start = alignDown(self.start, alignment);
        const end = try alignUp(self.end, alignment);
        return .{ .start = start, .end = end };
    }
};

pub fn alignDown(value: u64, alignment: u64) u64 {
    std.debug.assert(std.math.isPowerOfTwo(alignment));
    return value & ~(alignment - 1);
}

pub fn alignUp(value: u64, alignment: u64) !u64 {
    std.debug.assert(std.math.isPowerOfTwo(alignment));
    const mask = alignment - 1;
    if (value > std.math.maxInt(u64) - mask) return error.RangeOverflow;
    return (value + mask) & ~mask;
}

test "range alignment is conservative" {
    const range = try PhysRange.fromStartSize(0x1003, 0x2ffe);
    try std.testing.expectEqual(PhysRange{ .start = 0x2000, .end = 0x4000 }, (try range.alignedInward(page_size)).?);
    try std.testing.expectEqual(PhysRange{ .start = 0x1000, .end = 0x5000 }, try range.alignedOutward(page_size));
}

test "half-open overlap" {
    const a = PhysRange{ .start = 0x1000, .end = 0x2000 };
    const b = PhysRange{ .start = 0x2000, .end = 0x3000 };
    const c = PhysRange{ .start = 0x1800, .end = 0x2800 };
    try std.testing.expect(!a.overlaps(b));
    try std.testing.expect(a.overlaps(c));
}
