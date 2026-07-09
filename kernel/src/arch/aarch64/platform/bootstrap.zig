const build_options = @import("build_options");

const raspi3 = @import("raspi3/bootstrap.zig");
const virt = @import("virt/bootstrap.zig");

pub const device_ranges = switch (build_options.platform) {
    .raspi3 => raspi3.device_ranges,
    .virt => virt.device_ranges,
};
