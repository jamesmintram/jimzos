//! Machine-independent kernel initialization entered after architecture
//! bootstrap has installed the permanent memory map and core services.

const kprint = @import("../kprint.zig");
const boot = @import("boot_info.zig");
const bus = @import("../bus.zig");
const platform = @import("../arch/platform.zig");

const BootInfo = boot.BootInfo;

extern fn kmain(boot_info: *const BootInfo) callconv(.c) noreturn;
extern fn exit() noreturn;

/// Continue boot with permanent mappings and allocator services available.
pub fn run(info: *const BootInfo) noreturn {
    platform.configureDevices(info.fdt.tree, bus.cpuBus()) catch |err| {
        kprint.write("device configuration failed: {s}\r", .{@errorName(err)});
        exit();
    };
    kmain(info);
}
