// aarch64 boot stage 2: higher-half entry/exit glue (MMU on, virtual VAs).
// boot1_phys.zig branches here once the MMU is on.

const boot = @import("../../boot/init.zig");

extern var __bss_start: u8;
extern var __bss_end: u8;

/// Switch to the virtual kernel stack before entering normal Zig code.
export fn enter_virtual_addressing() callconv(.naked) noreturn {
    asm volatile (
        \\ adrp x2, __kernel_stack_top
        \\ add  x2, x2, #:lo12:__kernel_stack_top
        \\ msr  SPSel, #1
        \\ mov  sp, x2
        \\ b    init_arm
    );
}

/// Clear BSS on the virtual kernel stack, then enter architecture-independent
/// boot orchestration. `boot_x0` is preserved through the lower boot stages for
/// future use but is not currently part of the boot contract.
export fn init_arm(boot_x0: usize) callconv(.c) noreturn {
    @setRuntimeSafety(false);

    const start = @intFromPtr(&__bss_start);
    const end = @intFromPtr(&__bss_end);
    const words: [*]volatile usize = @ptrFromInt(start);
    const count = (end - start) / @sizeOf(usize);
    var index: usize = 0;
    while (index < count) : (index += 1) words[index] = 0;

    _ = boot_x0;
    boot.run();
}

/// Terminate via the Arm semihosting SYS_EXIT call used under QEMU.
export fn exit() noreturn {
    asm volatile (
        \\ mov w0, #0x18
        \\ mov x1, #0x20000
        \\ add x1, x1, #0x26
        \\ mov x2, #0
        \\ stp x1, x2, [sp, #-16]!
        \\ mov x1, sp
        \\ hlt #0xF000
        \\ b   .
    );

    unreachable;
}
