const build_options = @import("build_options");
const PhysRange = @import("phys_range").PhysRange;

const raspi3 = @import("platform/raspi3/platform.zig");
const virt = @import("platform/virt/platform.zig");

pub const bootstrap_device_range_count = switch (build_options.platform) {
    .raspi3 => raspi3.bootstrap_device_ranges.len,
    .virt => virt.bootstrap_device_ranges.len,
};

pub inline fn bootstrapDeviceRange(comptime index: usize) PhysRange {
    return switch (build_options.platform) {
        .raspi3 => raspi3.bootstrap_device_ranges[index],
        .virt => virt.bootstrap_device_ranges[index],
    };
}

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    switch (build_options.platform) {
        .raspi3 => try raspi3.prepareEarlyPl011(clock_hz),
        .virt => try virt.prepareEarlyPl011(clock_hz),
    }
}
