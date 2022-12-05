const regs = @import("types/regs.zig");

extern const __page_tables_phys_start: [*]usize;
extern const __page_tables_size: usize;

export fn preboot() linksection(".text.boot") callconv(.C) void {
    @setRuntimeSafety(false);

    // TODO: Ensure Stack pointer is configured BEFORE enterting here

    // Drop to EL3

    // scr_el3
    //  Disable MMU
    //  Disable Set Aarch64
    //  Set non secure state
    // MSR scr_el3

    // spsr_el3
    //  Use EL2's dedicated stack
    //  Configure drop to EL2
    //  Mask FIQ
    //  Mask IRQ
    //  Mask SError
    //  Mask Watchpoint, Breakpoint and Software
    // MSR spsr_el3

    // Drop to EL2

    // Drop to EL1

    //preboot_memset(__page_tables_phys_start, 0, __page_tables_size);

    // var d = __page_tables_phys_start;
    // comptime const count: usize =
    //     (__page_tables_size / @sizeOf(usize));
    // var n: usize = 0;

    var reg = regs.scr_el3{ .IRQ = 1, .FIQ = 1 };

    __page_tables_phys_start[0] = reg.bits();

    // Run tests on file save (on file just saved)

    // while (n < count) {
    //     __page_tables_phys_start[n] = 0; //__page_tables_phys_start[0] + 1;
    //     n += 1;
    //     //     d[0] = 0;
    //     //     d += 1;
    //     //     // n -= 1;
    //     //     // if (n == 0) break;
    //     //     // d += 1;
    // }

    // Setup identity map
    //
}
