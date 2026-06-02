pub const processor = struct {
    pub fn enable_interrupts() void {}
    pub fn disable_interrupts() void {}

    // inline so it folds into its caller — boot code runs before the higher
    // half is reachable, so it must not emit an out-of-line call into .text.
    pub inline fn flush() void {
        asm volatile ("dsb ish");
        asm volatile ("isb");
    }
};
