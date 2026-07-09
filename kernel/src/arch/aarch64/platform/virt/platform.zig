const PhysRange = @import("phys_range").PhysRange;

pub const bootstrap_device_ranges = [_]PhysRange{
    .{ .start = 0x09000000, .end = 0x09001000 }, // PL011
};

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    _ = clock_hz;
}
