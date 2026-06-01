//
//
// EL3
////////////////////////////////////////////////////////////////////////////////////////////
// SCR_EL3, SPSR_EL3

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/SCR-EL3--Secure-Configuration-Register
// Secure Configuration Register
// Top-level Secure-state control: exception routing to EL3, lower-EL execution state, and EL3 traps.
pub const SCR_EL3 = packed struct(usize) {
    NS: u1 = 0, //              Non-Secure
    IRQ: u1 = 0, //             Physical IRQ routing
    FIQ: u1 = 0, //             Physical FIQ routing
    EA: u1 = 0, //              External Abort
    RES1_4_5: u2 = 1, //        Reserved, RES1
    RES0_6: u1 = 0, //          Reserved, RES0
    SMD: u1 = 0, //             Secure Monitor Disable
    HCE: u1 = 0, //             Hypervisor Call Instruction Enable
    SIF: u1 = 0, //             Secure Instruction Fetch
    RW: u1 = 0, //              Execution state lower levels 32/64
    ST: u1 = 0, //              Traps Secure
    TWI: u1 = 0, //             Trap WFI  EL2, EL1, EL0
    TWE: u1 = 0, //             Traps WFE EL2, EL1, EL0
    TLOR: u1 = 0, //            Traps LOW registers
    TERR: u1 = 0, //            Traps error record access
    APK: u1 = 0, //             Traps Pointer Auth key registers
    API: u1 = 0, //             Traps Pointer Auth instructions
    EEL2: u1 = 0, //            Secure EL2 Enable
    EASE: u1 = 0, //            External Abort routed to SError vector
    NMEA: u1 = 0, //            Non-Maskable External Aborts
    FIEN: u1 = 0, //            Fault Injection Enable
    RES0_22_24: u3 = 0, //      Reserved, RES0
    EnSCXT: u1 = 0, //          Enable access to SCXTNUM_ELx
    ATA: u1 = 0, //             Allocation Tag Access
    FGTEn: u1 = 0, //           Fine-Grained Traps Enable
    ECVEn: u1 = 0, //           Enhanced Counter Virtualization Enable
    TWEDEn: u1 = 0, //          TWE Delay Enable
    TWEDEL: u4 = 0, //          TWE Delay
    TME: u1 = 0, //             Transactional Memory Enable
    AMVOFFEN: u1 = 0, //        Activity Monitors Virtual Offsets Enable
    EnAS0: u1 = 0, //           Enable ST64BV0 access
    ADEn: u1 = 0, //            Enable access to ACCDATA_EL1
    HXEn: u1 = 0, //            Enable HCRX_EL2 access
    RES0_39: u1 = 0, //         Reserved, RES0
    TRNDR: u1 = 0, //           Trap RNDR / RNDRRS reads
    EnTP2: u1 = 0, //           Trap TPIDR2_EL0 access
    RES0_42_47: u6 = 0, //      Reserved, RES0
    GPF: u1 = 0, //             Granule Protection Faults routing
    RES0_49_61: u13 = 0, //     Reserved, RES0
    NSE: u1 = 0, //             Secure/Non-Secure PA space (with NS)
    RES0_63: u1 = 0, //         Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) SCR_EL3 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], scr_el3"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr scr_el3, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty SCR_EL3 to bits" {
    const reg = SCR_EL3{};
    try expect(0x00000010 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/SPSR-EL3--Saved-Program-Status-Register--EL3-
// Saved Program Status Register
// PSTATE snapshot saved on exception entry to EL3, restored by ERET (mode, masks, flags).
pub const SPSR_EL3 = packed struct(usize) {
    pub const Mode = enum(u4) {
        EL0t = 0b0000, //       EL0
        EL1t = 0b0100, //       EL1, SP_EL0
        EL1h = 0b0101, //       EL1, SP_EL1
        EL2t = 0b1000, //       EL2, SP_EL0
        EL2h = 0b1001, //       EL2, SP_EL2
        EL3t = 0b1100, //       EL3, SP_EL0
        EL3h = 0b1101, //       EL3, SP_EL3
    };

    M: Mode = Mode.EL0t, //     Mode and stack pointer select
    M_4: u1 = 0, //             Execution state (0 = AArch64)
    RES0_5: u1 = 0, //          Reserved, RES0
    F: u1 = 0, //               FIQ interrupt mask
    I: u1 = 0, //               IRQ interrupt mask
    A: u1 = 0, //               SError (Abort) mask
    D: u1 = 0, //               Debug exception mask
    RES0_10: u10 = 0, //        Reserved, RES0
    IL: u1 = 0, //              Illegal Execution state
    SS: u1 = 0, //              Software Step
    PAN: u1 = 0, //             Privileged Access Never
    UA0: u1 = 0, //             User Access Override
    RES0_24: u4 = 0, //         Reserved, RES0
    V: u1 = 0, //               Overflow condition flag
    C: u1 = 0, //               Carry condition flag
    Z: u1 = 0, //               Zero condition flag
    N: u1 = 0, //               Negative condition flag
    RES0_32: u32 = 0, //        Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) SPSR_EL3 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], spsr_el3"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr spsr_el3, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty SPSR_EL3 to bits" {
    const reg =SPSR_EL3{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// EL2
////////////////////////////////////////////////////////////////////////////////////////////
// HCR_EL2, SPSR_EL2

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/HCR-EL2--Hypervisor-Configuration-Register
// Hypervisor Configuration Register
// Virtualization control: stage-2 translation, virtual interrupt injection, and traps to EL2.
pub const HCR_EL2 = packed struct(usize) {
    VM: u1 = 0, //              Virtualization (stage 2 MMU) enable
    SWIO: u1 = 0, //            Set/Way Invalidation Override
    PTW: u1 = 0, //             Protected Table Walk
    FMO: u1 = 0, //             Physical FIQ Routing
    IMO: u1 = 0, //             Physical IRQ Routing
    AMO: u1 = 0, //             Physical SError Routing
    VF: u1 = 0, //              Virtual FIQ pending
    VI: u1 = 0, //              Virtual IRQ pending
    VSE: u1 = 0, //             Virtual SError pending
    FB: u1 = 0, //              Force Broadcast
    BSU: u2 = 0, //             Barrier Shareability Upgrade
    DC: u1 = 0, //              Default Cacheable
    TWI: u1 = 0, //             Trap WFI
    TWE: u1 = 0, //             Trap WFE
    TID0: u1 = 0, //            Trap ID group 0
    TID1: u1 = 0, //            Trap ID group 1
    TID2: u1 = 0, //            Trap ID group 2
    TID3: u1 = 0, //            Trap ID group 3
    TSC: u1 = 0, //             Trap SMC instructions
    TIPDCP: u1 = 0, //          Trap IMP-DEF functionality (TIDCP)
    TACR: u1 = 0, //            Trap Auxiliary Control Registers
    TSW: u1 = 0, //             Trap cache maintenance by Set/Way
    TPCF: u1 = 0, //            Trap cache maintenance to PoC/PoP
    TPU: u1 = 0, //             Trap cache maintenance to PoU
    TTLB: u1 = 0, //            Trap TLB maintenance
    TVM: u1 = 0, //             Trap Virtual Memory controls
    TGE: u1 = 0, //             Trap General Exceptions (to EL2)
    TDZ: u1 = 0, //             Trap DC ZVA
    HCD: u1 = 0, //             HVC instruction Disable
    TRVM: u1 = 0, //            Trap Reads of Virtual Memory controls
    RW: u1 = 0, //              Lower levels Execution state (1 = AArch64)
    CD: u1 = 0, //              Stage 2 Data cache disable
    ID: u1 = 0, //              Stage 2 Instruction cache disable
    E2H: u1 = 0, //             EL2 Host (VHE)
    TLOR: u1 = 0, //            Trap LOR registers
    TERR: u1 = 0, //            Trap Error record accesses
    MIOCNCE: u1 = 0, //         Mismatched Inner/Outer Cacheable Non-Coherency
    RES0_39: u1 = 0, //         Reserved, RES0
    APK: u1 = 0, //             Trap Pointer Auth key registers
    API: u1 = 0, //             Trap Pointer Auth instructions
    NV: u1 = 0, //              Nested Virtualization
    NV1: u1 = 0, //             Nested Virtualization (NV1)
    AT: u1 = 0, //              Trap Address Translation instructions
    RES0_44: u20 = 0, //        Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) HCR_EL2 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], hcr_el2"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr hcr_el2, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty HCR_EL2 to bits" {
    const reg =HCR_EL2{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0601/2020-12/AArch64-Registers/SPSR-EL2--Saved-Program-Status-Register--EL2-
// Saved Program Status Register
// PSTATE snapshot saved on exception entry to EL2, restored by ERET (mode, masks, flags).
pub const SPSR_EL2 = packed struct(usize) {
    pub const Mode = enum(u4) {
        EL0t = 0b0000, //       EL0
        EL1t = 0b0100, //       EL1, SP_EL0
        EL1h = 0b0101, //       EL1, SP_EL1
        EL2t = 0b1000, //       EL2, SP_EL0
        EL2h = 0b1001, //       EL2, SP_EL2
    };

    M: Mode = Mode.EL0t, //     Mode and stack pointer select
    M_4: u1 = 0, //             Execution state (0 = AArch64)
    RES0_5: u1 = 0, //          Reserved, RES0
    F: u1 = 0, //               FIQ interrupt mask
    I: u1 = 0, //               IRQ interrupt mask
    A: u1 = 0, //               SError (Abort) mask
    D: u1 = 0, //               Debug exception mask
    BTYPE: u2 = 0, //           Branch Type Indicator
    SSBS: u1 = 0, //            Speculative Store Bypass Safe
    RES0_13: u7 = 0, //         Reserved, RES0
    IL: u1 = 0, //              Illegal Execution state
    SS: u1 = 0, //              Software Step
    PAN: u1 = 0, //             Privileged Access Never
    UA0: u1 = 0, //             User Access Override
    DIT: u1 = 0, //             Data Independent Timing
    TCO: u1 = 0, //             Tag Check Override
    RES0_26: u2 = 0, //         Reserved, RES0
    V: u1 = 0, //               Overflow condition flag
    C: u1 = 0, //               Carry condition flag
    Z: u1 = 0, //               Zero condition flag
    N: u1 = 0, //               Negative condition flag
    RES0_32: u32 = 0, //        Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) SPSR_EL2 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], spsr_el2"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr spsr_el2, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty SPSR_EL2 to bits" {
    const reg =SPSR_EL2{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// EL1
////////////////////////////////////////////////////////////////////////////////////////////
// TCR_EL1, SCTLR_EL1, ID_AA64MMFR0_EL1, MAIR_EL1, ESR_EL1

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/TCR-EL1--Translation-Control-Register--EL1-
// Translation Control Register
// EL1&0 stage-1 MMU controls: TTBR0/TTBR1 region sizes, granule sizes, and walk cacheability/shareability.
pub const TCR_EL1 = packed struct(usize) {
    pub const Shareability = enum(u2) {
        NonSharable = 0b00,
        OuterShareable = 0b10,
        InnerShareable = 0b11,
    };
    pub const OuterCacheability = enum(u2) {
        NormalMemory_Outer_NonCacheable = 0b00,
        NormalMemory_Outer_WriteBack_ReadAllocate_WriteAllocateCacheable = 0b01,
        NormalMemory_Outer_WriteThrough_ReadAllocate_NoWriteAllocateCacheable = 0b10,
        NormalMemory_Outer_WriteBack_ReadAllocate_NoWriteAllocateCacheable = 0b11,
    };
    pub const InnerCacheability = enum(u2) {
        NormalMemory_Inner_NonCacheable = 0b00,
        NormalMemory_Inner_WriteBack_ReadAllocate_WriteAllocateCacheable = 0b01,
        NormalMemory_Inner_WriteThrough_ReadAllocate_NoWriteAllocateCacheable = 0b10,
        NormalMemory_Inner_WriteBack_ReadAllocate_NoWriteAllocateCacheable = 0b11,
    };

    // In AArch64, you have 3 possible translation granules to choose from,
    // each of which results in a different set of page sizes:
    // - 4KB granule: 4KB, 2MB, and 1GB pages.
    // - 16KB granule: 16KB and 32MB pages.
    // - 64KB granule: 64KB and 512MB pages.
    //
    // (https://stackoverflow.com/a/34269498)

    pub const TG1GranuleSize = enum(u2) {
        Size_16KB = 0b01,
        Size_4KB = 0b10,
        Size_64KB = 0b11,
    };

    pub const TG0GranuleSize = enum(u2) {
        Size_4KB = 0b00,
        Size_64KB = 0b01,
        Size_16KB = 0b10,
    };

    T0SZ: u6 = 0, //            Size offset for the TTBR0 region (2^(64-T0SZ))
    RES0_0: u1 = 0, //          Reserved, RES0
    EPD0: u1 = 0, //            Translation table walk disable, TTBR0
    IRGN0: InnerCacheability = InnerCacheability.NormalMemory_Inner_NonCacheable, // Inner cacheability, TTBR0 walks
    ORGN0: OuterCacheability = OuterCacheability.NormalMemory_Outer_NonCacheable, // Outer cacheability, TTBR0 walks
    SH0: Shareability = Shareability.NonSharable, // Shareability, TTBR0 walks
    TG0: TG0GranuleSize = TG0GranuleSize.Size_4KB, // Granule size, TTBR0

    T1SZ: u6 = 0, //            Size offset for the TTBR1 region (2^(64-T1SZ))
    A1: u1 = 0, //              ASID select (0 = TTBR0, 1 = TTBR1)
    EPD1: u1 = 0, //            Translation table walk disable, TTBR1
    IRGN1: InnerCacheability = InnerCacheability.NormalMemory_Inner_NonCacheable, // Inner cacheability, TTBR1 walks
    ORGN1: OuterCacheability = OuterCacheability.NormalMemory_Outer_NonCacheable, // Outer cacheability, TTBR1 walks
    SH1: Shareability = Shareability.NonSharable, // Shareability, TTBR1 walks
    TG1: TG1GranuleSize = TG1GranuleSize.Size_4KB, // Granule size, TTBR1

    IPS: u3 = 0, //             Intermediate Physical Address Size
    RES0_1: u1 = 0, //          Reserved, RES0
    AS: u1 = 0, //              ASID Size (0 = 8-bit, 1 = 16-bit)
    TBI0: u1 = 0, //            Top Byte Ignored, TTBR0
    TBI1: u1 = 0, //            Top Byte Ignored, TTBR1
    HA: u1 = 0, //              Hardware Access flag update
    HD: u1 = 0, //              Hardware Dirty state management
    HPD0: u1 = 0, //            Hierarchical Permission Disable, TTBR0
    HPD1: u1 = 0, //            Hierarchical Permission Disable, TTBR1
    HWU059: u1 = 0, //          Hardware Use of block/page bit[59], TTBR0
    HWU060: u1 = 0, //          Hardware Use of block/page bit[60], TTBR0
    HWU061: u1 = 0, //          Hardware Use of block/page bit[61], TTBR0
    HWU062: u1 = 0, //          Hardware Use of block/page bit[62], TTBR0

    HWU159: u1 = 0, //          Hardware Use of block/page bit[59], TTBR1
    HWU160: u1 = 0, //          Hardware Use of block/page bit[60], TTBR1
    HWU161: u1 = 0, //          Hardware Use of block/page bit[61], TTBR1
    HWU162: u1 = 0, //          Hardware Use of block/page bit[62], TTBR1

    TBID0: u1 = 0, //           Top Byte Ignored applies to data only, TTBR0
    TBID1: u1 = 0, //           Top Byte Ignored applies to data only, TTBR1
    NFD0: u1 = 0, //            Non-Fault translation walk disable, TTBR0
    NFD1: u1 = 0, //            Non-Fault translation walk disable, TTBR1

    E0PD0: u1 = 0, //           EL0 access prevention, TTBR0
    E0PD1: u1 = 0, //           EL0 access prevention, TTBR1
    TCMA0: u1 = 0, //           Unprivileged Tag Check override, TTBR0
    TCMA1: u1 = 0, //           Unprivileged Tag Check override, TTBR1
    DS: u1 = 0, //              52-bit output address support (LPA2)
    RES0_2: u4 = 0, //          Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) TCR_EL1 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], tcr_el1"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr tcr_el1, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty TCR_EL1 to bits" {
    const reg =TCR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-03/AArch64-Registers/SCTLR-EL1--System-Control-Register--EL1-
// System Control Register
// Top-level EL1&0 control: MMU and cache enables, alignment checking, endianness, and EL0 traps.
pub const SCTLR_EL1 = packed struct(usize) {
    M: u1 = 0, //               MMU enable
    A: u1 = 0, //               Alignment check enable
    C: u1 = 0, //               Data/unified cache enable
    SA: u1 = 0, //              Stack Alignment check enable (EL1)
    SA0: u1 = 0, //             Stack Alignment check enable (EL0)
    CP15BEN: u1 = 0, //         CP15 Barrier enable (AArch32)
    RES0_6: u1 = 0, //          Reserved, RES0
    ITD: u1 = 0, //             IT Disable (AArch32)
    SED: u1 = 0, //             SETEND Disable (AArch32)
    UMA: u1 = 0, //             User Mask Access (trap DAIF from EL0)
    RES0_10: u1 = 0, //         Reserved, RES0
    RES1_11: u1 = 1, //         Reserved, RES1
    I: u1 = 0, //               Instruction cache enable
    EnDB: u1 = 0, //            Enable Pointer Auth (APDBKey)
    DZE: u1 = 0, //             Trap DC ZVA (EL0)
    UCT: u1 = 0, //             Trap CTR_EL0 access (EL0)
    nTWI: u1 = 0, //            Don't trap WFI (EL0)
    RES0_17: u1 = 0, //         Reserved, RES0
    nTWE: u1 = 0, //            Don't trap WFE (EL0)
    WXN: u1 = 0, //             Write permission implies Execute-Never
    RES1_20: u1 = 1, //         Reserved, RES1
    IESB: u1 = 0, //            Implicit Error Synchronization event
    RES1_22: u1 = 1, //         Reserved, RES1
    SPAN: u1 = 0, //            Set PAN on exception
    E0E: u1 = 0, //             EL0 data Endianness
    EE: u1 = 0, //              EL1 data Endianness (exception state)
    UCI: u1 = 0, //             Trap cache maintenance (EL0)
    EnDA: u1 = 0, //            Enable Pointer Auth (APDAKey)
    nTLSMD: u1 = 0, //          No Trap LD/ST Multiple to Device (AArch32)
    LSMAOE: u1 = 0, //          LD/ST Multiple Atomicity and Ordering (AArch32)
    EnIB: u1 = 0, //            Enable Pointer Auth (APIBKey)
    EnIA: u1 = 0, //            Enable Pointer Auth (APIAKey)
    RES0_32: u3 = 0, //         Reserved, RES0
    BT0: u1 = 0, //             PAC Branch Target check (EL0)
    BT1: u1 = 0, //             PAC Branch Target check (EL1)
    ITFSB: u1 = 0, //           Tag Fault sync on entry to EL1
    TCF0: u2 = 0, //            Tag Check Fault control (EL0)
    TCF: u2 = 0, //             Tag Check Fault control (EL1)
    ATA0: u1 = 0, //            Allocation Tag Access (EL0)
    ATA: u1 = 0, //             Allocation Tag Access (EL1)
    DSSBS: u1 = 0, //           Default SSBS value on exception
    TWEDEn: u1 = 0, //          TWE Delay Enable
    TWEDEL: u4 = 0, //          TWE Delay
    RES0_50: u4 = 0, //         Reserved, RES0
    EnASR: u1 = 0, //           Enable EL0 access to ST64BV
    EnAS0: u1 = 0, //           Enable EL0 access to ST64BV0
    EnALS: u1 = 0, //           Enable EL0 access to LD64B/ST64B
    EPAN: u1 = 0, //            Enhanced Privileged Access Never
    RES0_58: u6 = 0, //         Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) SCTLR_EL1 {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], sctlr_el1"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr sctlr_el1, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty SCTLR_EL1 to bits" {
    const reg =SCTLR_EL1{};
    try expect(0x00500800 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ID-AA64MMFR0-EL1--AArch64-Memory-Model-Feature-Register-0
// Memory Model Feature Register 0
// Read-only: implemented memory system — physical address range, ASID size, and supported granules.
pub const ID_AA64MMFR0_EL1 = packed struct(usize) {
    PARangeLo: u2 = 0, //       Physical Address Range, low bits
    PARangeHi: u2 = 0, //       Physical Address Range, high bits
    ASIDBits: u4 = 0, //        Number of ASID bits
    BigEnd: u4 = 0, //          Mixed-endian support (EL1/EL2/EL3)
    SNSMem: u4 = 0, //          Secure / Non-Secure memory distinction
    BigEndEL0: u4 = 0, //       Mixed-endian support at EL0
    TGran16: u4 = 0, //         16KB granule support (stage 1)
    TGran64: u4 = 0, //         64KB granule support (stage 1)
    TGran4: u4 = 0, //          4KB granule support (stage 1)
    TGran16_2: u4 = 0, //       16KB granule support (stage 2)
    TGran64_2: u4 = 0, //       64KB granule support (stage 2)
    TGran4_2: u4 = 0, //        4KB granule support (stage 2)
    ExS: u4 = 0, //             Disabling context-synchronizing exception entry/exit
    RES0: u8 = 0, //            Reserved, RES0
    FGT: u4 = 0, //             Fine-Grained Trap support
    ECV: u4 = 0, //             Enhanced Counter Virtualization support

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) Self {
        return @bitCast(bits);
    }

    pub inline fn read() Self {
        var register: usize = 0;

        asm ("mrs %[value], ID_AA64MMFR0_EL1"
            : [value] "=r" (register),
        );

        return Self.fromBits(register);
    }
};
test "empty ID_AA64MMFR0_EL1 to bits" {
    const reg =ID_AA64MMFR0_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2020-12/AArch64-Registers/MAIR-EL1--Memory-Attribute-Indirection-Register--EL1-?lang=en#fieldset_0-63_0
// Memory Attribute Indirection Register
// The eight memory-attribute encodings that page-table entries select via their AttrIndx field.
pub const MAIR_EL1 = packed struct(usize) {
    const AttributeEncoding = u8;

    Attr0: AttributeEncoding = 0, // Attribute 0 encoding (selected by AttrIndx = 0)
    Attr1: AttributeEncoding = 0, // Attribute 1 encoding (selected by AttrIndx = 1)
    Attr2: AttributeEncoding = 0, // Attribute 2 encoding (selected by AttrIndx = 2)
    Attr3: AttributeEncoding = 0, // Attribute 3 encoding (selected by AttrIndx = 3)
    Attr4: AttributeEncoding = 0, // Attribute 4 encoding (selected by AttrIndx = 4)
    Attr5: AttributeEncoding = 0, // Attribute 5 encoding (selected by AttrIndx = 5)
    Attr6: AttributeEncoding = 0, // Attribute 6 encoding (selected by AttrIndx = 6)
    Attr7: AttributeEncoding = 0, // Attribute 7 encoding (selected by AttrIndx = 7)

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) MAIR_EL1 {
        return @bitCast(bits);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr mair_el1, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty MAIR_EL1 to bits" {
    const reg =MAIR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-
// Exception Syndrome Register (EL1)
// Records the cause of an exception taken to EL1: exception class (EC) plus class-specific syndrome (ISS).
pub const ESR_EL1 = packed struct(usize) {
    const ExceptionClass = enum(u6) {
        Unknown = 0b000000, //              https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_0
        Trapped_WFX = 0b000001, //          https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_1
        Trapped_MCR_MRC_1 = 0b000011, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_2
        Trapped_MCRR_MRRC = 0b000100, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_4
        Trapped_MCR_MRC_2 = 0b000101, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_2

        Trapped_LDC_STC = 0b000110, //      https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_5
        Trapped_SVE_SIMD = 0b000111, //     https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_6
        Trapped_LD64B_ST64B = 0b001010, //  https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_3
        Trapped_MRRC = 0b001100, //         https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_4

        BranchTargetEx = 0b001101, //       https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_23
        IllegalExState = 0b001110, //       https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_8

        SVC_In_32 = 0b010001, //            https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_9
        SVC_In_64 = 0b010101, //            https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_9

        Trapped_MSR_MRS_64 = 0b011000, //   https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_12
        Access_SVE = 0b011001, //           https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_7
        Pointer_Auth_Ex = 0b011100, //      https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_25

        Ins_Abort_Lower_El = 0b100000, //   https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fields et_0-24_0_14
        Ins_Abort_Same_El = 0b100001, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_14

        PC_Align_Fault = 0b100010, //       https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_8

        Data_Abort_Lower_El = 0b100100, //  https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_15
        Data_Abort_Same_El = 0b100101, //   https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_15

        SP_Align_Fault = 0b100110, //       https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_8

        Trapped_FP_Ex_32 = 0b101000, //     https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_16
        Trapped_FP_Ex_64 = 0b101100, //     https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_16

        SError = 0b101111, //               https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_17

        BP_Ex_Lower_El = 0b110000, //       https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_18
        BP_Ex_Same_El = 0b110001, //        https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_18

        SW_Step_Lower_El = 0b110010, //     https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_19
        SW_Step_Same_El = 0b110011, //      https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_19

        Watch_Point_Lower_El = 0b110100, // https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_20
        Watch_Point_Same_El = 0b110101, //  https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_20

        BreakPoint_Ins_32 = 0b111000, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_21
        BreakPoint_Ins_64 = 0b111100, //    https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-?lang=en#fieldset_0-24_0_21
    };

    ISS: u25 = 0, //            Instruction Specific Syndrome
    IL: u1 = 0, //              Instruction Length (0 = 16-bit, 1 = 32-bit)
    EC: ExceptionClass = ExceptionClass.Unknown, // Exception Class
    ISS2: u5 = 0, //            Instruction Specific Syndrome 2
    RES0_37: u27 = 0, //        Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) ESR_EL1 {
        return @bitCast(bits);
    }
};
test "empty ESR_EL1 to bits" {
    const reg =ESR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// Misc
////////////////////////////////////////////////////////////////////////////////////////////
// DAIF

// https://developer.arm.com/documentation/ddi0601/2020-12/AArch64-Registers/DAIF--Interrupt-Mask-Bits?lang=en
// DAIF, Interrupt Mask Bits
// PSTATE interrupt masks: D (Debug), A (SError), I (IRQ), F (FIQ); set a bit to mask that exception.
pub const DAIF = packed struct(usize) {
    RES0_0: u6 = 0, //          Reserved, RES0
    F: u1 = 0, //               FIQ interrupt mask
    I: u1 = 0, //               IRQ interrupt mask
    A: u1 = 0, //               SError (Abort) mask
    D: u1 = 0, //               Debug exception mask
    RES0_10_64: u54 = 0, //     Reserved, RES0

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: usize) DAIF {
        return @bitCast(bits);
    }
};
test "empty DAIF to bits" {
    const reg =DAIF{};
    try expect(0x00000000 == reg.toBits());
}

// Current Exception Level, decoded from CurrentEL[3:2].
pub const ExceptionLevel = enum(u8) {
    EL0 = 0, //                 Application / unprivileged
    EL1 = 1, //                 OS kernel
    EL2 = 2, //                 Hypervisor
    EL3 = 3, //                 Secure Monitor / firmware

    pub inline fn read() ExceptionLevel {
        var current_exception_level: usize = 0;

        asm ("mrs  %[value], CurrentEL"
            : [value] "=r" (current_exception_level),
        );

        current_exception_level = (current_exception_level >> 2) & 0x3;
        return @enumFromInt(current_exception_level);
    }
};

// Stack pointer for EL1 (SP_EL1), e.g. to set up the EL1 stack from a higher EL.
pub const SP_EL1 = struct {
    pub inline fn write(sp_el1: usize) void {
        asm volatile ("msr sp_el1, %[value]"
            :
            : [value] "r" (sp_el1),
        );
    }
};

const std = @import("std");
const expect = std.testing.expect;

// TODO: Where should this live?
pub const Register = union(enum) {
    ReadOnly: u32,
    WriteOnly: u32,
    ReadWrite: u32,
};
