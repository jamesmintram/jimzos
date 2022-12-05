pub const processor = struct {
    pub fn enable_interrupts() void {}
    pub fn disable_interrupts() void {}

    pub fn flush() void {
        asm volatile ("dsb ish");
        asm volatile ("isb");
    }
};
