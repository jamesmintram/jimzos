const build_options = @import("build_options");

const raspi3 = @import("platform/raspi3/platform.zig");
const virt = @import("platform/virt/platform.zig");

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    switch (build_options.platform) {
        .raspi3 => try raspi3.prepareEarlyPl011(clock_hz),
        .virt => try virt.prepareEarlyPl011(clock_hz),
    }
}
