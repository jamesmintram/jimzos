pub inline fn enter_el2_from_el3() void {
    asm volatile (
        \\    adr x0, 1f
        \\    msr elr_el3, x0
        \\    eret
        \\ 1:
        ::: .{ .x0 = true });
}

pub inline fn enter_el1_from_el2() void {
    asm volatile (
        \\    adr x0, 1f
        \\    msr elr_el2, x0
        \\    eret
        \\ 1:
        ::: .{ .x0 = true });
}
