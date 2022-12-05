const regs = @import("types/regs.zig");
const processor = @import("processor.zig");
const asm64 = @import("asm.zig");

extern const __page_tables_phys_start: [*]usize;
extern const __page_tables_size: usize;

fn build_identity_map() void {}

fn activate_mmu() void {
    var mair = regs.MAIR_EL1{
        .Attr0 = 0xFF,
        .Attr1 = 0x04,
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

fn drop_to_el2() void {
    var scr_el3 = regs.SCR_EL3{
        .ST = 1, //  Don't trap access to Counter-timer Physical Secure registers
        .RW = 1, //  Lower level to use Aarch64
        .NS = 1, //  Non-secure state
        .HCE = 1, // Enable Hypervisor instructions at all levels
    };
    regs.SCR_EL3.write(scr_el3);

    var spsr_el3 = regs.SPSR_EL3{
        .A = 1, //
        .I = 1, //
        .F = 1, //
        .D = 1, //

        .M = regs.SPSR_EL3.Mode.EL2t,
    };
    regs.SPSR_EL3.write(spsr_el3);

    asm64.enter_el2_from_el3();
}

fn drop_to_el1() void {
    var hcr_el2 = regs.HCR_EL2{
        .RW = 1, //
    };
    regs.HCR_EL2.write(hcr_el2);

    // Set up initial exception stack
    regs.SP_EL1.write(0x40000);

    var spsr_el2 = regs.SPSR_EL2{
        .A = 1, //
        .I = 1, //
        .F = 1, //
        .M = regs.SPSR_EL2.Mode.EL1t, //
    };
    regs.SPSR_EL2.write(spsr_el2);

    asm64.enter_el1_from_el2();
}

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

    // TODO: Ensure Stack pointer is configured BEFORE enterting here

    drop_to_initial_el1();

    //
    // build_identity_map(allocator, root_table);
    // switch_to_page_table(page_tables_phys_start);

    //__page_tables_phys_start[0] = reg.toBits();

    activate_mmu();
}
