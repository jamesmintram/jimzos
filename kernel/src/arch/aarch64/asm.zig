pub inline fn enter_el2_from_el3() void {
    asm volatile (
        \\    adr x0, entered_el2
        \\    msr elr_el3, x0
        \\    eret
        \\ entered_el2:
        ::: "x0");
}

pub inline fn enter_el1_from_el2() void {
    asm volatile (
        \\    adr x0, entered_el1
        \\    msr elr_el2, x0
        \\    eret
        \\ entered_el1:
        ::: "x0");
}
