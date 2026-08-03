//! AArch64 implementations of shared CPU operations.

/// Wait until an interrupt or another architecturally defined event wakes this
/// processing element.
pub inline fn waitForInterrupt() void {
    asm volatile ("wfi" ::: .{ .memory = true });
}

/// Full-system data memory barrier.
pub inline fn dataMemoryBarrier() void {
    asm volatile ("dmb sy" ::: .{ .memory = true });
}

/// Full-system data synchronization barrier.
pub inline fn dataSynchronizationBarrier() void {
    asm volatile ("dsb sy" ::: .{ .memory = true });
}

pub inline fn instructionSynchronizationBarrier() void {
    asm volatile ("isb" ::: .{ .memory = true });
}

/// Set only the IRQ mask in PSTATE.DAIF.
pub inline fn maskIrq() void {
    asm volatile ("msr daifset, #2" ::: .{ .memory = true });
}

/// Clear only the IRQ mask in PSTATE.DAIF.
pub inline fn unmaskIrq() void {
    asm volatile ("msr daifclr, #2" ::: .{ .memory = true });
}

/// Return the opaque kernel thread pointer maintained by context-switch code.
pub inline fn currentThreadPointer() usize {
    return asm volatile ("mrs %[thread], tpidr_el1"
        : [thread] "=&r" (-> usize),
    );
}
