//! AArch64 platform integration and root-device configuration.

const DeviceTree = @import("DeviceTree");
const build_options = @import("build_options");
const bus = @import("../../bus.zig");
const fdt_util = @import("../../fdt.zig");
const interrupt = @import("../../interrupt.zig");
const kprint = @import("../../kprint.zig");
const timer = @import("../../timer.zig");
const generic_timer_fdt = @import("dev/generic_timer_fdt.zig");
const gic_v3_fdt = @import("dev/gic_v3_fdt.zig");

const raspi3 = @import("platform/raspi3/platform.zig");
const virt = @import("platform/virt/platform.zig");

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    switch (build_options.platform) {
        .raspi3 => try raspi3.prepareEarlyPl011(clock_hz),
        .virt => try virt.prepareEarlyPl011(clock_hz),
    }
}

/// Attach the root interrupt controller and its first consumer after the
/// permanent kernel map has made runtime MMIO mapping available.
pub fn configureDevices(fdt: DeviceTree, parent_bus: bus.Bus) !void {
    attachInterruptDevices(fdt, parent_bus) catch |err| switch (err) {
        error.GicV3NotFound, error.GenericTimerNotFound => {
            kprint.write("interrupt devices unavailable: {s}\r", .{@errorName(err)});
        },
        else => return err,
    };
}

fn attachInterruptDevices(fdt: DeviceTree, parent_bus: bus.Bus) !void {
    const gic_node = (try findEnabledCompatible(
        fdt,
        "arm,gic-v3",
        .root_children,
    )) orelse return error.GicV3NotFound;
    const gic = try gic_v3_fdt.attach(.{
        .tree = fdt,
        .node = gic_node,
        .parent_bus = parent_bus,
    });
    try interrupt.bindRootController(gic.root_controller);

    const timer_node = (try findEnabledCompatible(
        fdt,
        "arm,armv8-timer",
        .all_descendants,
    )) orelse (try findEnabledCompatible(
        fdt,
        "arm,armv7-timer",
        .all_descendants,
    )) orelse return error.GenericTimerNotFound;
    const attached_timer = try generic_timer_fdt.attach(.{
        .tree = fdt,
        .node = timer_node,
        .parent_bus = parent_bus,
    });
    try timer.installSystem(attached_timer.device, attached_timer.interrupt_resource);

    kprint.write("GICv3: distributor=0x{x} redistributor=0x{x}\r", .{
        gic.distributor.physicalBase(),
        gic.redistributors.physicalBase(),
    });
    kprint.write("timer: CNTP interrupt {} at {} Hz\r", .{
        attached_timer.interrupt_resource.route.line,
        timer.default_ticks_per_second,
    });
}

const MatchScope = enum {
    root_children,
    all_descendants,
};

/// Mainbus selects enabled root devices. The architectural timer has no MMIO
/// resource, so retaining its historical descendant match is harmless while
/// simple-bus attachment is still being introduced.
fn findEnabledCompatible(
    fdt: DeviceTree,
    compatible: []const u8,
    comptime scope: MatchScope,
) !?DeviceTree.Node {
    var nodes = try fdt.nodeCompatibleMatchIterator(
        .root,
        switch (scope) {
            .root_children => .direct_children,
            .all_descendants => .all_children,
        },
        compatible,
    );

    while (try nodes.next(fdt)) |match| {
        if (try fdt_util.statusOkay(fdt, match.node.node)) {
            return match.node.node;
        }
    }
    return null;
}
