const build_options = @import("build_options");

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    switch (build_options.platform) {
        .raspi3 => try @import("platform/raspi3.zig").prepareEarlyPl011(clock_hz),
        .virt => try @import("platform/virt.zig").prepareEarlyPl011(clock_hz),
    }
}
