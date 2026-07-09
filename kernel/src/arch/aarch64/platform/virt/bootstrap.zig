const PhysRange = @import("phys_range").PhysRange;

pub const device_ranges = [2]?PhysRange{
    .{ .start = 0x09000000, .end = 0x09001000 }, // PL011
    null,
};
