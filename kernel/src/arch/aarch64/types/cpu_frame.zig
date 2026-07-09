pub const CPUFrame = extern struct {
    tf_sp: u64 align(1),
    tf_lr: u64 align(1),
    tf_elr: u64 align(1),
    tf_spsr: u32 align(1),
    tf_esr: u32 align(1),
    tf_x: [30]u64 align(1),
};

comptime {
    if (@offsetOf(CPUFrame, "tf_sp") != 0 or
        @offsetOf(CPUFrame, "tf_lr") != 8 or
        @offsetOf(CPUFrame, "tf_elr") != 16 or
        @offsetOf(CPUFrame, "tf_spsr") != 24 or
        @offsetOf(CPUFrame, "tf_esr") != 28 or
        @offsetOf(CPUFrame, "tf_x") != 32 or
        @sizeOf(CPUFrame) != 272)
    {
        @compileError("unexpected AArch64 CPU frame layout");
    }
}
