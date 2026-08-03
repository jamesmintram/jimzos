//! FDT attachment for the Arm architected timer.

const fdt_util = @import("../../../fdt.zig");
const interrupt = @import("../../../interrupt.zig");
const timer = @import("../../../timer.zig");
const generic_timer = @import("generic_timer.zig");

var attached_timer: generic_timer.Timer = undefined;
var attached = false;

pub const Attachment = struct {
    device: timer.Device,
    interrupt_resource: interrupt.Resource,
};

/// The generic timer binding orders its interrupts as secure physical,
/// non-secure physical, virtual, and hypervisor. JimZOS drives CNTP, so it
/// consumes entry 1 rather than embedding a GIC PPI number in the timer driver.
const cntp_interrupt_index: usize = 1;

/// Attach the enabled architectural timer and return capabilities that kernel
/// policy may assign to a timer role.
pub fn attach(args: fdt_util.FdtAttachArgs) !Attachment {
    if (attached) return error.GenericTimerAlreadyAttached;

    const interrupt_resource = try args.interrupt(cntp_interrupt_index);
    attached_timer = try generic_timer.Timer.init();
    attached = true;

    return .{
        .device = attached_timer.device(),
        .interrupt_resource = interrupt_resource,
    };
}
