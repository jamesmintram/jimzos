const PhysicalRange = @import("../types.zig").PhysicalRange;

pub const bootstrap_device_ranges = [_]PhysicalRange{
    .{ .start = 0x09000000, .end = 0x09001000 }, // PL011
};

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    _ = clock_hz;
}
