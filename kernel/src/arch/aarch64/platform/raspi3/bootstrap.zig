const PhysRange = @import("phys_range").PhysRange;

pub const device_ranges = [2]?PhysRange{
    .{ .start = 0x3f00b000, .end = 0x3f00c000 }, // VideoCore mailbox
    .{ .start = 0x3f200000, .end = 0x3f202000 }, // GPIO and PL011
};
