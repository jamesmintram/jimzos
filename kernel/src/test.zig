pub const DeviceTree = @import("DeviceTree");
pub const phys_range = @import("phys_range");
pub const boot_info = @import("boot/boot_info.zig");
pub const fdt_boot = @import("boot/fdt_boot.zig");
pub const bus = @import("bus.zig");
pub const interrupt = @import("interrupt.zig");
pub const mmio_region = @import("io/mmio_region.zig");
pub const timer = @import("timer.zig");
pub const fdt = @import("fdt.zig");
pub const gic_v3_fdt = @import("arch/aarch64/dev/gic_v3_fdt.zig");
pub const page_frame_manager = @import("vm/page_frame_manager.zig");
pub const translation_map = @import("arch/aarch64/mmu/translation_map.zig");

comptime {
    _ = @import("arch/aarch64/types/regs.zig");
    _ = @import("drivers/serial/pl011.zig");
}
