// aarch64 kernel entry/exit glue (the Zig successor to kernel_entry.S).
//
// preboot.zig branches to `enter_virtual_addressing` once the MMU is on, so
// this code runs in the higher half.

extern fn kmain() callconv(.c) noreturn;

// Linker-script symbols (see linker.ld). 16-byte aligned; only their addresses
// are used.
extern var __bss_start: u8;
extern var __bss_end: u8;

/// First code executed in the higher half. Switching the stack pointer must be
/// done in asm — changing SP inside a normal function would invalidate its
/// frame — so this is a naked trampoline that sets the virtual SP and branches
/// into Zig.
export fn enter_virtual_addressing() callconv(.naked) noreturn {
    asm volatile (
        \\ adrp x2, __kernel_stack_top
        \\ add  x2, x2, #:lo12:__kernel_stack_top
        \\ msr  SPSel, #1            // switch to SP_EL1
        \\ mov  sp, x2
        \\ b    kmain_trampoline
    );
}

/// Runs on the virtual kernel stack: zero .bss, then hand off to the kernel.
export fn kmain_trampoline() callconv(.c) noreturn {
    @setRuntimeSafety(false);

    // Globals assume .bss is zero. Clear it a word at a time; `volatile` keeps
    // this from being lowered to a memset libcall. __bss_start/_end are
    // 16-byte aligned, so the range is a whole number of usizes.
    const start = @intFromPtr(&__bss_start);
    const end = @intFromPtr(&__bss_end);
    const words: [*]volatile usize = @ptrFromInt(start);
    const count = (end - start) / @sizeOf(usize);
    var i: usize = 0;
    while (i < count) : (i += 1) words[i] = 0;

    kmain();
}

/// Terminate via the Arm semihosting SYS_EXIT call (used under QEMU). Declared
/// `extern fn exit() noreturn` by panic.zig and kernel.zig.
export fn exit() callconv(.naked) noreturn {
    asm volatile (
        \\ mov w0, #0x18             // SYS_EXIT
        \\ mov x1, #0x20000
        \\ add x1, x1, #0x26         // reason = ADP_Stopped_ApplicationExit (0x20026)
        \\ mov x2, #0                // exit code
        \\ stp x1, x2, [sp, #-16]!   // parameter block { reason, code }
        \\ mov x1, sp
        \\ hlt #0xF000               // semihosting trap
        \\ b   .                     // never returns; spin if semihosting is off
    );
}
