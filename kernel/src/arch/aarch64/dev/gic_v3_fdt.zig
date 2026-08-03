const std = @import("std");
const fdt_util = @import("../../../fdt.zig");
const interrupt = @import("../../../interrupt.zig");
const gic_v3 = @import("gic_v3.zig");
const MmioRegion = @import("../../../io/mmio_region.zig").MmioRegion;

const default_redistributor_stride: usize = 0x2_0000;

var attached_controller: gic_v3.GicV3 = undefined;
var attached = false;

pub const Attachment = struct {
    distributor: MmioRegion,
    redistributors: MmioRegion,
    root_controller: interrupt.RootController,
};

/// Attach the root GIC from the FDT and publish its consumer-facing interface
/// under the matching provider node. The platform retains the returned root
/// capability and decides whether to bind it to the CPU IRQ entry.
pub fn attach(args: fdt_util.FdtAttachArgs) !Attachment {
    if (attached) return error.GicV3AlreadyAttached;

    const region_count = (try fdt_util.u32Property(
        args.tree,
        args.node,
        "#redistributor-regions",
    )) orelse 1;
    if (region_count != 1) return error.UnsupportedRedistributorRegions;

    const distributor_resource = args.mmio(0) catch |err| switch (err) {
        error.MmioIndexOutOfRange => return error.MissingDistributorRegisters,
        else => return err,
    };
    const redistributor_resource = args.mmio(1) catch |err| switch (err) {
        error.MmioIndexOutOfRange => return error.MissingRedistributorRegisters,
        else => return err,
    };
    const stride_value = (try fdt_util.u64Property(
        args.tree,
        args.node,
        "redistributor-stride",
    )) orelse default_redistributor_stride;
    const stride = std.math.cast(usize, stride_value) orelse
        return error.RedistributorStrideOverflow;

    const config = gic_v3.Config{
        .distributor = try distributor_resource.map(),
        .redistributors = try redistributor_resource.map(),
        .redistributor_stride = stride,
    };

    attached_controller = try gic_v3.GicV3.init(config);
    try fdt_util.registerInterruptController(.{
        .node = args.node,
        .controller = attached_controller.interruptController(),
        .decode = decodeInterrupt,
    });
    attached = true;

    return .{
        .distributor = config.distributor,
        .redistributors = config.redistributors,
        .root_controller = attached_controller.rootController(),
    };
}

/// Decode the standard three-cell GIC interrupt binding. Provider selection is
/// handled by the FDT interrupt-controller registry before this is called.
pub fn decodeInterrupt(specifier: fdt_util.InterruptSpecifier) !interrupt.Route {
    if (specifier.cellCount() != 3) return error.InvalidGicInterruptSpecifier;

    const kind = try specifier.cell(0);
    const relative_line = try specifier.cell(1);
    const line_base: u32 = switch (kind) {
        0 => 32, // SPI
        1 => 16, // PPI
        else => return error.UnsupportedGicInterruptType,
    };
    if ((kind == 1 and relative_line >= 16) or
        (kind == 0 and relative_line >= 988))
    {
        return error.InvalidGicInterruptLine;
    }

    const trigger: interrupt.Trigger = switch (try specifier.cell(2)) {
        1 => .edge_rising,
        2 => .edge_falling,
        4 => .level_high,
        8 => .level_low,
        else => return error.UnsupportedGicInterruptFlags,
    };
    return .{
        .line = try std.math.add(u32, line_base, relative_line),
        .trigger = trigger,
    };
}
