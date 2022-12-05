//
//
// EL3
////////////////////////////////////////////////////////////////////////////////////////////
// SCR_EL3, SPSR_EL3

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/SCR-EL3--Secure-Configuration-Register
// Secure Configuration Register
pub const SCR_EL3 = packed struct(usize) {
    NS: u1 = 0, //              Non-Secure
    IRQ: u1 = 0, //
    FIQ: u1 = 0, //
    EA: u1 = 0, //              External Abort
    RES1_4_5: u2 = 1, //
    RES0_6: u1 = 0, //
    SMD: u1 = 0, //             Secure Monitor Disable
    HCE: u1 = 0, //             Hypervisor Call Instruction Enable
    SIF: u1 = 0, //             Secure Instruction Fetch
    RW: u1 = 0, //              Execution state lower levels 32/64
    ST: u1 = 0, //              Traps Secure
    TWI: u1 = 0, //             Trap WFI  EL2, EL1, EL0
    TWE: u1 = 0, //             Traps WFE EL2, EL1, EL0
    TLOR: u1 = 0, //            Traps LOW registers
    TERR: u1 = 0, //            Traps error record access
    APK: u1 = 0, //             Traps
    API: u1 = 0, //
    EEL2: u1 = 0, //
    EASE: u1 = 0, //
    NMEA: u1 = 0, //
    FIEN: u1 = 0, //
    RES0_22_24: u3 = 0, //
    EnSCXT: u1 = 0, //
    ATA: u1 = 0, //
    FGTEn: u1 = 0, //
    ECVEn: u1 = 0, //
    TWEDEn: u1 = 0, //
    TWEDEL: u4 = 0, //
    TME: u1 = 0, //
    AMVOFFEN: u1 = 0, //
    EnAS0: u1 = 0, //
    ADEn: u1 = 0, //
    HXEn: u1 = 0, //
    RES0_39: u1 = 0, //
    TRNDR: u1 = 0, //
    EnTP2: u1 = 0, //
    RES0_42_47: u6 = 0, //
    GPF: u1 = 0, //
    RES0_49_61: u13 = 0, //
    NSE: u1 = 0, //
    RES0_63: u1 = 0, //

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) SCR_EL3 {
        return @bitCast(Self, bits);
    }
};
test "empty SCR_EL3 to bits" {
    var reg = SCR_EL3{};
    try expect(0x00000010 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/SPSR-EL3--Saved-Program-Status-Register--EL3-
// Saved Program Status Register
pub const SPSR_EL3 = packed struct(usize) {
    const Mode = enum(u4) {
        EL0t = 0b0000, //
        EL1t = 0b0100, //
        EL1h = 0b0101, //
        EL2t = 0b1000, //
        EL2h = 0b1001, //
        EL3t = 0b1100, //
        EL3h = 0b1101, //
    };

    M: Mode = Mode.EL0t,
    M_4: u1 = 0,
    RES0_5: u1 = 0,
    F: u1 = 0,
    I: u1 = 0,
    A: u1 = 0,
    D: u1 = 0,
    RES0_10: u10 = 0,
    IL: u1 = 0,
    SS: u1 = 0,
    PAN: u1 = 0,
    UA0: u1 = 0,
    RES0_24: u4 = 0,
    V: u1 = 0,
    C: u1 = 0,
    Z: u1 = 0,
    N: u1 = 0,
    RES0_32: u32 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) SPSR_EL3 {
        return @bitCast(Self, bits);
    }
};
test "empty SPSR_EL3 to bits" {
    var reg = SPSR_EL3{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// EL2
////////////////////////////////////////////////////////////////////////////////////////////
// HCR_EL2, SPSR_EL2

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/HCR-EL2--Hypervisor-Configuration-Register
// Hypervisor Configuration Register
pub const HCR_EL2 = packed struct(usize) {
    VM: u1 = 0,
    SWIO: u1 = 0,
    PTW: u1 = 0,
    FMO: u1 = 0,
    IMO: u1 = 0,
    AMO: u1 = 0,
    VF: u1 = 0,
    VI: u1 = 0,
    VSE: u1 = 0,
    FB: u1 = 0,
    BSU: u2 = 0,
    DC: u1 = 0,
    TWI: u1 = 0,
    TWE: u1 = 0,
    TID0: u1 = 0,
    TID1: u1 = 0,
    TID2: u1 = 0,
    TID3: u1 = 0,
    TSC: u1 = 0,
    TIPDCP: u1 = 0,
    TACR: u1 = 0,
    TSW: u1 = 0,
    TPCF: u1 = 0,
    TPU: u1 = 0,
    TTLB: u1 = 0,
    TVM: u1 = 0,
    TGE: u1 = 0,
    TDZ: u1 = 0,
    HCD: u1 = 0,
    TRVM: u1 = 0,
    RW: u1 = 0,
    CD: u1 = 0,
    ID: u1 = 0,
    E2H: u1 = 0,
    TLOR: u1 = 0,
    TERR: u1 = 0,
    MIOCNCE: u1 = 0,
    RES0_39: u1 = 0,
    APK: u1 = 0,
    API: u1 = 0,
    NV: u1 = 0,
    NV1: u1 = 0,
    AT: u1 = 0,
    RES0_44: u20 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) HCR_EL2 {
        return @bitCast(Self, bits);
    }
};
test "empty HCR_EL2 to bits" {
    var reg = HCR_EL2{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0601/2020-12/AArch64-Registers/SPSR-EL2--Saved-Program-Status-Register--EL2-
// Saved Program Status Register
pub const SPSR_EL2 = packed struct(usize) {
    const Mode = enum(u4) {
        EL0t = 0b0000, //
        EL1t = 0b0100, //
        EL1h = 0b0101, //
        EL2t = 0b1000, //
        EL2h = 0b1001, //
    };

    M: Mode = Mode.EL0t,
    M_4: u1 = 0,
    RES0_5: u1 = 0,
    F: u1 = 0,
    I: u1 = 0,
    A: u1 = 0,
    D: u1 = 0,
    BTYPE: u2 = 0,
    SSBS: u1 = 0,
    RES0_13: u7 = 0,
    IL: u1 = 0,
    SS: u1 = 0,
    PAN: u1 = 0,
    UA0: u1 = 0,
    DIT: u1 = 0,
    TCO: u1 = 0,
    RES0_26: u2 = 0,
    V: u1 = 0,
    C: u1 = 0,
    Z: u1 = 0,
    N: u1 = 0,
    RES0_32: u32 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) SPSR_EL2 {
        return @bitCast(Self, bits);
    }
};
test "empty SPSR_EL2 to bits" {
    var reg = SPSR_EL2{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// EL1
////////////////////////////////////////////////////////////////////////////////////////////
// TCR_EL1, SCTLR_EL1, ID_AA64MMFR0_EL1, MAIR_EL1, ESR_EL1

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/TCR-EL1--Translation-Control-Register--EL1-
// Translation Control Register
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

    T0SZ: u6 = 0,
    RES0_0: u1 = 0,
    EPD0: u1 = 0,
    IRGN0: InnerCacheability = InnerCacheability.NormalMemory_Inner_NonCacheable,
    ORGN0: OuterCacheability = OuterCacheability.NormalMemory_Outer_NonCacheable,
    SH0: Shareability = Shareability.NonSharable,
    TG0: TG0GranuleSize = TG0GranuleSize.Size_4KB,

    T1SZ: u6 = 0,
    A1: u1 = 0,
    EPD1: u1 = 0,
    IRGN1: InnerCacheability = InnerCacheability.NormalMemory_Inner_NonCacheable,
    ORGN1: OuterCacheability = OuterCacheability.NormalMemory_Outer_NonCacheable,
    SH1: Shareability = Shareability.NonSharable,
    TG1: TG1GranuleSize = TG1GranuleSize.Size_4KB,

    IPS: u3 = 0,
    RES0_1: u1 = 0,
    AS: u1 = 0,
    TBI0: u1 = 0,
    TBI1: u1 = 0,
    HA: u1 = 0,
    HD: u1 = 0,
    HPD0: u1 = 0,
    HPD1: u1 = 0,
    HWU059: u1 = 0,
    HWU060: u1 = 0,
    HWU061: u1 = 0,
    HWU062: u1 = 0,

    HWU159: u1 = 0,
    HWU160: u1 = 0,
    HWU161: u1 = 0,
    HWU162: u1 = 0,

    TBID0: u1 = 0,
    TBID1: u1 = 0,
    NFD0: u1 = 0,
    NFD1: u1 = 0,

    E0PD0: u1 = 0,
    E0PD1: u1 = 0,
    TCMA0: u1 = 0,
    TCMA1: u1 = 0,
    DS: u1 = 0,
    RES0_2: u4 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) TCR_EL1 {
        return @bitCast(Self, bits);
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
    var reg = TCR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-03/AArch64-Registers/SCTLR-EL1--System-Control-Register--EL1-
// System Control Register
pub const SCTLR_EL1 = packed struct(usize) {
    M: u1 = 0,
    A: u1 = 0,
    C: u1 = 0,
    SA: u1 = 0,
    SA0: u1 = 0,
    CP15BEN: u1 = 0,
    RES0_6: u1 = 0,
    ITD: u1 = 0,
    SED: u1 = 0,
    UMA: u1 = 0,
    RES0_10: u1 = 0,
    RES1_11: u1 = 1,
    I: u1 = 0,
    EnDB: u1 = 0,
    DZE: u1 = 0,
    UCT: u1 = 0,
    nTWI: u1 = 0,
    RES0_17: u1 = 0,
    nTWE: u1 = 0,
    WXN: u1 = 0,
    RES1_20: u1 = 1,
    IESB: u1 = 0,
    RES1_22: u1 = 1,
    SPAN: u1 = 0,
    E0E: u1 = 0,
    EE: u1 = 0,
    UCI: u1 = 0,
    EnDA: u1 = 0,
    nTLSMD: u1 = 0,
    LSMAOE: u1 = 0,
    EnIB: u1 = 0,
    EnIA: u1 = 0,
    RES0_32: u3 = 0,
    BT0: u1 = 0,
    BT1: u1 = 0,
    ITFSB: u1 = 0,
    TCF0: u2 = 0,
    TCF: u2 = 0,
    ATA0: u1 = 0,
    ATA: u1 = 0,
    DSSBS: u1 = 0,
    TWEDEn: u1 = 0,
    TWEDEL: u4 = 0,
    RES0_50: u4 = 0,
    EnASR: u1 = 0,
    EnAS0: u1 = 0,
    EnALS: u1 = 0,
    EPAN: u1 = 0,
    RES0_58: u6 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) SCTLR_EL1 {
        return @bitCast(Self, bits);
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
    var reg = SCTLR_EL1{};
    try expect(0x00500800 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ID-AA64MMFR0-EL1--AArch64-Memory-Model-Feature-Register-0
// Memory Model Feature Register 0
pub const ID_AA64MMFR0_EL1 = packed struct(usize) {
    PARangeLo: u2 = 0,
    PARangeHi: u2 = 0,
    ASIDBits: u4 = 0,
    BigEnd: u4 = 0,
    SNSMem: u4 = 0,
    BigEndEL0: u4 = 0,
    TGran16: u4 = 0,
    TGran64: u4 = 0,
    TGran4: u4 = 0,
    TGran16_2: u4 = 0,
    TGran64_2: u4 = 0,
    TGran4_2: u4 = 0,
    ExS: u4 = 0,
    RES0: u8 = 0,
    FGT: u4 = 0,
    ECV: u4 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) Self {
        return @bitCast(Self, bits);
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
    var reg = ID_AA64MMFR0_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2020-12/AArch64-Registers/MAIR-EL1--Memory-Attribute-Indirection-Register--EL1-?lang=en#fieldset_0-63_0
// Memory Attribute Indirection Register
pub const MAIR_EL1 = packed struct(usize) {
    const AttributeEncoding = u8;

    Attr0: AttributeEncoding = 0,
    Attr1: AttributeEncoding = 0,
    Attr2: AttributeEncoding = 0,
    Attr3: AttributeEncoding = 0,
    Attr4: AttributeEncoding = 0,
    Attr5: AttributeEncoding = 0,
    Attr6: AttributeEncoding = 0,
    Attr7: AttributeEncoding = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) MAIR_EL1 {
        return @bitCast(Self, bits);
    }

    pub inline fn write(self: Self) void {
        asm volatile ("msr mair_el1, %[value]"
            :
            : [value] "r" (Self.toBits(self)),
        );
    }
};
test "empty MAIR_EL1 to bits" {
    var reg = MAIR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

// https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/ESR-EL1--Exception-Syndrome-Register--EL1-
// Exception Syndrome Register (EL1)
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

    ISS: u25 = 0,
    IL: u1 = 0,
    EC: ExceptionClass = ExceptionClass.Unknown,
    ISS2: u5 = 0,
    RES0_37: u27 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) ESR_EL1 {
        return @bitCast(Self, bits);
    }
};
test "empty ESR_EL1 to bits" {
    var reg = ESR_EL1{};
    try expect(0x00000000 == reg.toBits());
}

//
//
// Misc
////////////////////////////////////////////////////////////////////////////////////////////
// DAIF

// https://developer.arm.com/documentation/ddi0601/2020-12/AArch64-Registers/DAIF--Interrupt-Mask-Bits?lang=en
// DAIF, Interrupt Mask Bits
pub const DAIF = packed struct(usize) {
    RES0_0: u6 = 0,
    F: u1 = 0,
    I: u1 = 0,
    A: u1 = 0,
    D: u1 = 0,
    RES0_10_64: u54 = 0,

    const Self = @This();
    pub inline fn toBits(self: Self) usize {
        return @bitCast(usize, self);
    }

    pub inline fn fromBits(bits: usize) DAIF {
        return @bitCast(Self, bits);
    }
};
test "empty DAIF to bits" {
    var reg = DAIF{};
    try expect(0x00000000 == reg.toBits());
}

pub const ExceptionLevel = enum(u8) {
    EL0 = 0,
    EL1 = 1,
    EL2 = 2,
    EL3 = 3,

    pub inline fn read() ExceptionLevel {
        var current_exception_level: usize = 0;

        asm ("mrs  %[value], CurrentEL"
            : [value] "=r" (current_exception_level),
        );

        current_exception_level = (current_exception_level >> 2) & 0x3;
        return @intToEnum(ExceptionLevel, current_exception_level);
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
