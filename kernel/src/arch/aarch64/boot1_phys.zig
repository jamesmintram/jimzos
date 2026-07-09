// aarch64 boot stage 1: physical, MMU-off bring-up. Drops to EL1, builds the
// identity map, enables the MMU, then hands off to boot2_virt (enter_higher_half
// -> enter_virtual_addressing) once running in the higher half.

const regs = @import("types/regs.zig");
const processor = @import("processor.zig");
const asm64 = @import("asm.zig");
const build_options = @import("build_options");
const platform = @import("platform.zig");

/// Load absolute linker-symbol values without going through the higher-half
/// GOT, which is out of ADRP range while this code executes at low addresses.
inline fn pageTablesPhysStart() usize {
    return asm volatile ("ldr %[value], =__page_tables_phys_start"
        : [value] "=r" (-> usize),
    );
}

inline fn pageTablesSize() usize {
    return asm volatile ("ldr %[value], =__page_tables_size"
        : [value] "=r" (-> usize),
    );
}

inline fn kernelStackGuardPhys() usize {
    return asm volatile ("ldr %[value], =__kernel_stack_guard_phys"
        : [value] "=r" (-> usize),
    );
}

inline fn bootStackPhys() usize {
    return asm volatile ("ldr %[value], =__boot_phys_stack"
        : [value] "=r" (-> usize),
    );
}

inline fn kernelPhysStart() usize {
    return asm volatile ("ldr %[value], =__kernel_phys_start"
        : [value] "=r" (-> usize),
    );
}

inline fn kernelPhysEnd() usize {
    return asm volatile ("ldr %[value], =__kernel_phys_end"
        : [value] "=r" (-> usize),
    );
}

// --- Page-table geometry (4 KiB granule, 4-level walk) ---------------------
const TABLE_SIZE: usize = 0x1000;
const ENTRIES_PER_TABLE: usize = 512;
const PAGE_SIZE: usize = 0x1000;
const TABLE_ADDRESS_MASK: usize = 0x0000fffffffff000;

// --- Descriptor bits (mirror consts.h) -------------------------------------
const DESC_VALID: usize = 0b11; //  valid + table descriptor (L0-L2) / page descriptor (L3)
const MM_ACCESS: usize = 1 << 10; // Access Flag (AF); without it the first access faults
const PT_OSH: usize = 2 << 8; //    outer shareable
const PT_ISH: usize = 3 << 8; //    inner shareable
const PT_MEM: usize = 0 << 2; //    AttrIndx 0 -> MAIR Attr0 (normal write-back)
const PT_DEV: usize = 1 << 2; //    AttrIndx 1 -> MAIR Attr1 (device)

const TableArena = struct {
    next: usize,
    end: usize,

    inline fn allocate(self: *TableArena) usize {
        if (self.next + TABLE_SIZE > self.end) hangBoot();
        const physical = self.next;
        self.next += TABLE_SIZE;
        const table: [*]volatile usize = @ptrFromInt(physical);
        var i: usize = 0;
        while (i < ENTRIES_PER_TABLE) : (i += 1) table[i] = 0;
        return physical;
    }
};

inline fn tableAt(physical: usize) [*]volatile usize {
    return @ptrFromInt(physical);
}

inline fn ensureNext(parent_phys: usize, index: usize, arena: *TableArena) usize {
    const parent = tableAt(parent_phys);
    if ((parent[index] & DESC_VALID) != 0) return parent[index] & TABLE_ADDRESS_MASK;
    const child = arena.allocate();
    parent[index] = child | DESC_VALID;
    return child;
}

inline fn mapPage(root_phys: usize, physical: usize, flags: usize, arena: *TableArena) void {
    const l1_phys = ensureNext(root_phys, (physical >> 39) & 0x1ff, arena);
    const l2_phys = ensureNext(l1_phys, (physical >> 30) & 0x1ff, arena);
    const l3_phys = ensureNext(l2_phys, (physical >> 21) & 0x1ff, arena);
    const l3 = tableAt(l3_phys);
    l3[(physical >> 12) & 0x1ff] = physical | flags;
}

inline fn mapRange(root_phys: usize, start: usize, end: usize, flags: usize, arena: *TableArena) void {
    var physical = start & ~(PAGE_SIZE - 1);
    const aligned_end = (end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    while (physical < aligned_end) : (physical += PAGE_SIZE) {
        if (physical != kernelStackGuardPhys()) mapPage(root_phys, physical, flags, arena);
    }
}

inline fn readFdtSize() usize {
    const header: [*]volatile u32 = @ptrFromInt(build_options.fdt_phys);
    if (@byteSwap(header[0]) != 0xd00dfeed) hangBoot();
    const size: usize = @byteSwap(header[1]);
    if (size < 40 or size > 2 * 1024 * 1024) hangBoot();
    return size;
}

inline fn mapEarlyDevices(root_phys: usize, arena: *TableArena) void {
    const flags = DESC_VALID | MM_ACCESS | PT_OSH | PT_DEV;
    inline for (0..platform.bootstrap_device_range_count) |index| {
        const range = platform.bootstrapDeviceRange(index);
        mapRange(root_phys, range.start, range.end, flags, arena);
    }
}

inline fn hangBoot() noreturn {
    while (true) asm volatile ("wfe");
}

/// Build a deliberately small temporary map. The same root is used for TTBR0
/// and TTBR1 until the higher-half kernel installs its FDT-derived final map.
fn build_identity_map() linksection(".text.boot") void {
    @setRuntimeSafety(false);

    const pt_base = pageTablesPhysStart();
    const pt_size = pageTablesSize();
    // The upper half remains untouched for the higher-half transition mapper.
    var arena = TableArena{ .next = pt_base, .end = pt_base + pt_size / 2 };
    const root = arena.allocate();
    if (root != pt_base) hangBoot();

    const normal_flags = DESC_VALID | MM_ACCESS | PT_ISH | PT_MEM;
    mapRange(root, kernelPhysStart(), kernelPhysEnd(), normal_flags, &arena);
    const fdt_size = readFdtSize();
    mapRange(root, build_options.fdt_phys, build_options.fdt_phys + fdt_size, normal_flags, &arena);
    mapEarlyDevices(root, &arena);
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
    const pt_base = pageTablesPhysStart();
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

    regs.SP_EL1.write(bootStackPhys());

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
/// the high half); enter_virtual_addressing sets the virtual SP, then init_arm
/// clears BSS and calls kmain, so it never returns. boot_x0 (x0 at reset) is
/// forwarded untouched to init_arm.
fn enter_higher_half(boot_x0: usize) linksection(".text.boot") noreturn {
    @setRuntimeSafety(false);

    // Bind boot_x0 to x0 so it survives the indirect branch into
    // enter_virtual_addressing -> init_arm, which expects it as arg0.
    asm volatile (
        \\ ldr x8, =_vectors
        \\ msr vbar_el1, x8
        \\ ldr x8, =enter_virtual_addressing
        \\ br  x8
        :
        : [x0] "{x0}" (boot_x0),
        : .{ .x8 = true });

    unreachable;
}

export fn boot1_phys(boot_x0: usize) linksection(".text.boot") callconv(.c) void {
    @setRuntimeSafety(false);

    // TODO: Ensure Stack pointer is configured BEFORE entering here

    // boot_x0 is whatever x0 held at the reset entry (boot0 leaves x0 untouched).
    // Keep it live across the bring-up calls below — the compiler parks it in a
    // callee-saved register — and forward it to the kernel via x0. On raspi3b
    // this is not the DTB; on a generic armv8/EFI boot it will be (see init_arm).

    drop_to_initial_el1();

    // Disable interrupts

    build_identity_map();
    activate_mmu();

    enter_higher_half(boot_x0);
}
