const regs = @import("types/regs.zig");
const processor = @import("processor.zig");
const asm64 = @import("asm.zig");

// Symbols from linker.ld. They are absolute linker symbols, so we only ever
// take their *addresses* — never read through them:
//   &__page_tables_phys_start -> physical base of the page-table pool
//   &__page_tables_size       -> reserved pool size in bytes (the symbol's
//                                value *is* the size)
extern const __page_tables_phys_start: u8;
extern const __page_tables_size: u8;
extern const __kernel_stack_guard_phys: u8;

// --- Page-table geometry (4 KiB granule, 4-level walk) ---------------------
// Pool layout, which must match linker.ld's
//   __page_tables_size = ((3 + 512) * 0x1000)
//   table[0]       L0 / PGD
//   table[1]       L1 / PUD
//   table[2]       L2 / PMD
//   table[3..515)  L3 / PTE  (512 contiguous leaf tables)
const TABLE_SIZE: usize = 0x1000;
const ENTRIES_PER_TABLE: usize = 512;
const SECTION_SIZE: usize = 0x1000; // each L3 entry maps one 4 KiB page

// --- Descriptor bits (mirror consts.h) -------------------------------------
const DESC_VALID: usize = 0b11; //  valid + table descriptor (L0-L2) / page descriptor (L3)
const MM_ACCESS: usize = 1 << 10; // Access Flag (AF); without it the first access faults
const PT_OSH: usize = 2 << 8; //    outer shareable
const PT_ISH: usize = 3 << 8; //    inner shareable
const PT_MEM: usize = 0 << 2; //    AttrIndx 0 -> MAIR Attr0 (normal write-back)
const PT_DEV: usize = 1 << 2; //    AttrIndx 1 -> MAIR Attr1 (device)

// --- Physical address map (Raspberry Pi 3) ---------------------------------
const RAM_TOP: usize = 0x3EFFFFFF; //   top of normal cacheable RAM
const MMIO_BASE: usize = 0x3F000000; // peripheral / MMIO window
const MMIO_TOP: usize = 0x3FFFFFFF; //  top of MMIO

/// Build one set of page tables that identity-maps all of physical memory.
///
/// The same root table is installed in both TTBR0 (low VAs, used by this boot
/// code which is still executing at physical addresses) and TTBR1 (high VAs,
/// the kernel's higher half: VA = PA + kernel_va_base). Because the table walk
/// ignores the top 16 bits of the VA, a single identity map serves both halves.
fn build_identity_map() linksection(".text.boot") void {
    @setRuntimeSafety(false);

    const pt_base = @intFromPtr(&__page_tables_phys_start);
    const pt_size = @intFromPtr(&__page_tables_size);

    // `volatile` so the zeroing loop below is emitted as real stores instead of
    // being lowered to a `memset` libcall: memset lives in the kernel's high
    // .text, which this MMU-off boot code cannot reach.
    const tables: [*]volatile usize = @ptrFromInt(pt_base);

    // Clear the whole pool so every entry we do not fill stays an invalid
    // descriptor (bit 0 = 0).
    const total_entries = pt_size / @sizeOf(usize);
    var i: usize = 0;
    while (i < total_entries) : (i += 1) tables[i] = 0;

    // L0 (PGD)[0] -> L1 (PUD) table
    tables[0] = (pt_base + TABLE_SIZE) | DESC_VALID;

    // L1 (PUD)[0] -> L2 (PMD) table
    const pud = tables + ENTRIES_PER_TABLE;
    pud[0] = (pt_base + 2 * TABLE_SIZE) | DESC_VALID;

    // L2 (PMD)[0..512) -> the 512 contiguous L3 (PTE) tables
    const pmd = tables + 2 * ENTRIES_PER_TABLE;
    var pte_table = pt_base + 3 * TABLE_SIZE;
    i = 0;
    while (i < ENTRIES_PER_TABLE) : (i += 1) {
        pmd[i] = pte_table | DESC_VALID;
        pte_table += TABLE_SIZE;
    }

    // L3 (PTE): identity-map every 4 KiB page. The 512 PTE tables are laid out
    // contiguously, so we can address them as one flat array.
    const pte = tables + 3 * ENTRIES_PER_TABLE;
    var idx: usize = 0;

    // Normal cacheable RAM: 0x0 .. RAM_TOP (inner shareable, MAIR idx 0).
    const ram_flags = DESC_VALID | MM_ACCESS | PT_ISH | PT_MEM;
    var phys: usize = 0;
    while (phys <= RAM_TOP) : (phys += SECTION_SIZE) {
        pte[idx] = phys | ram_flags;
        idx += 1;
    }

    // Device / MMIO: MMIO_BASE .. MMIO_TOP (outer shareable, MAIR idx 1).
    const dev_flags = DESC_VALID | MM_ACCESS | PT_OSH | PT_DEV;
    phys = MMIO_BASE;
    while (phys <= MMIO_TOP) : (phys += SECTION_SIZE) {
        pte[idx] = phys | dev_flags;
        idx += 1;
    }

    // Punch a hole for the kernel stack guard page: clear its leaf entry so an
    // overflow past __kernel_stack_limit faults instead of silently corrupting
    // whatever is below it. pte[i] maps physical page i, so the index is
    // guard_phys >> page_shift. Both TTBR0 and TTBR1 walk this same entry.
    const guard_phys = @intFromPtr(&__kernel_stack_guard_phys);
    pte[guard_phys / SECTION_SIZE] = 0;
}

fn activate_mmu() linksection(".text.boot") void {
    @setRuntimeSafety(false);

    const mair = regs.MAIR_EL1{
        .Attr0 = 0xFF,
        .Attr1 = 0x04,
    };
    regs.MAIR_EL1.write(mair);

    // Install the identity-mapped root in both halves (see build_identity_map):
    //   TTBR0 -> low  VAs (identity, for this boot code)
    //   TTBR1 -> high VAs (kernel higher half)
    const pt_base = @intFromPtr(&__page_tables_phys_start);
    regs.TTBR0_EL1.write(pt_base);
    regs.TTBR1_EL1.write(pt_base);

    const feature_register = regs.ID_AA64MMFR0_EL1.read();

    const tcr = regs.TCR_EL1{
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

    // Ensure the table writes and the system-register setup are visible before
    // the MMU starts walking.
    processor.processor.flush();

    var sctlr_el1 = regs.SCTLR_EL1.read();
    sctlr_el1.M = 1; // MMU enable
    sctlr_el1.C = 1; // data / unified cache enable
    sctlr_el1.I = 1; // instruction cache enable
    regs.SCTLR_EL1.write(sctlr_el1);

    // Synchronise so the following instructions execute translated.
    processor.processor.flush();
}

fn drop_to_el2() linksection(".text.boot") void {
    @setRuntimeSafety(false);

    const scr_el3 = regs.SCR_EL3{
        .ST = 1, //  Don't trap access to Counter-timer Physical Secure registers
        .RW = 1, //  Lower level to use Aarch64
        .NS = 1, //  Non-secure state
        .HCE = 1, // Enable Hypervisor instructions at all levels
    };
    regs.SCR_EL3.write(scr_el3);

    const spsr_el3 = regs.SPSR_EL3{
        .A = 1, //
        .I = 1, //
        .F = 1, //
        .D = 1, //

        .M = regs.SPSR_EL3.Mode.EL2t,
    };
    regs.SPSR_EL3.write(spsr_el3);

    asm64.enter_el2_from_el3();
}

fn drop_to_el1() linksection(".text.boot") void {
    @setRuntimeSafety(false);

    const hcr_el2 = regs.HCR_EL2{
        .RW = 1, //
    };
    regs.HCR_EL2.write(hcr_el2);

    // Set up initial exception stack
    regs.SP_EL1.write(0x40000);

    const spsr_el2 = regs.SPSR_EL2{
        .A = 1, //
        .I = 1, //
        .F = 1, //
        .M = regs.SPSR_EL2.Mode.EL1t, //
    };
    regs.SPSR_EL2.write(spsr_el2);

    asm64.enter_el1_from_el2();
}

fn drop_to_initial_el1() linksection(".text.boot") void {
    @setRuntimeSafety(false);

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

/// Hand control to the kernel proper, which is linked in the higher half. A
/// normal branch cannot reach VA 0xFFFF…, so load the absolute address from a
/// literal pool and branch to it indirectly. Runs with the MMU on (TTBR1 maps
/// the high half); enter_virtual_addressing sets the virtual SP, clears BSS
/// and calls kmain, so it never returns.
fn enter_higher_half() linksection(".text.boot") noreturn {
    @setRuntimeSafety(false);

    asm volatile (
        \\ ldr x8, =_vectors
        \\ msr vbar_el1, x8
        \\ ldr x8, =enter_virtual_addressing
        \\ br  x8
        ::: .{ .x8 = true });

    unreachable;
}

export fn preboot() linksection(".text.boot") callconv(.c) void {
    @setRuntimeSafety(false);

    // TODO: Ensure Stack pointer is configured BEFORE entering here

    drop_to_initial_el1();

    build_identity_map();
    activate_mmu();

    enter_higher_half();
}
