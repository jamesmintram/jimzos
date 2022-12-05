const regs = @import("types/regs.zig");
const processor = @import("processor.zig");

extern const __page_tables_phys_start: [*]usize;
extern const __page_tables_size: usize;

fn build_identity_map() void {}

fn activate_mmu() void {
    var mair = regs.MAIR_EL1{
        .Attr0 = 0xFF,
        .Attr1 = 0b00000100,
    };
    regs.MAIR_EL1.write(mair);

    var feature_register = regs.ID_AA64MMFR0_EL1.read();

    var tcr = regs.TCR_EL1{
        .SH1 = regs.TCR_EL1.Shareability.InnerShareable,
        .ORGN1 = regs.TCR_EL1.OuterCacheability.NormalMemory_Outer_WriteBack_ReadAllocate_WriteAllocateCacheable,
        .IRGN1 = regs.TCR_EL1.InnerCacheability.NormalMemory_Inner_WriteBack_ReadAllocate_WriteAllocateCacheable,
        .T1SZ = 16,

        .SH0 = regs.TCR_EL1.Shareability.InnerShareable,
        .ORGN0 = regs.TCR_EL1.OuterCacheability.NormalMemory_Outer_WriteBack_ReadAllocate_WriteAllocateCacheable,
        .IRGN0 = regs.TCR_EL1.InnerCacheability.NormalMemory_Inner_WriteBack_ReadAllocate_WriteAllocateCacheable,
        .T0SZ = 16,

        .TG1 = regs.TCR_EL1.TG1GranuleSize.Size_4KB,
        .TG0 = regs.TCR_EL1.TG0GranuleSize.Size_4KB,

        // Auto detect the Intermediate Physical Address Size
        .IPS = feature_register.PARangeLo,
    };

    regs.TCR_EL1.write(tcr);

    var sctlr_el1 = regs.SCTLR_EL1.read();
    sctlr_el1.M = 1;
    regs.SCTLR_EL1.write(sctlr_el1);

    processor.processor.flush();
}

fn drop_to_el2() void {}
fn drop_to_el1() void {}

fn drop_to_initial_el1() void {
    switch (regs.ExceptionLevel.read()) {
        .EL3 => {
            drop_to_el2();
            drop_to_el1();
        },
        .EL2 => {
            drop_to_el1();
        },
        .EL1 => {
            // no-op
        },
        else => {
            // Panic!
        },
    }
}

export fn preboot() linksection(".text.boot") callconv(.C) void {
    @setRuntimeSafety(false);

    drop_to_initial_el1();

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

    var reg = regs.SCR_EL3{ .IRQ = 1, .FIQ = 1 };

    __page_tables_phys_start[0] = reg.toBits();

    // build_identity_map(allocator, root_table);
    // setup_quickmap_page_table(allocator, root_table);
    // setup_kernel_page_directory(root_table);

    // switch_to_page_table(page_tables_phys_start);

    activate_mmu();

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
