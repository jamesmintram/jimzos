pub inline fn enter_el2_from_el3() void {
    // Preserve the active Zig call chain across the exception-level
    // transition. EL2h selects SP_EL2 after ERET.
    asm volatile (
        \\    mov x1, sp
        \\    msr sp_el2, x1
        \\    adr x0, 1f
        \\    msr elr_el3, x0
        \\    eret
        \\ 1:
        ::: .{ .x0 = true, .x1 = true });
}

pub inline fn enter_el1_from_el2() void {
    // Preserve the active Zig call chain across the exception-level
    // transition. EL1h selects SP_EL1 after ERET.
    asm volatile (
        \\    mov x1, sp
        \\    msr sp_el1, x1
        \\    adr x0, 1f
        \\    msr elr_el2, x0
        \\    eret
        \\ 1:
        ::: .{ .x0 = true, .x1 = true });
}
