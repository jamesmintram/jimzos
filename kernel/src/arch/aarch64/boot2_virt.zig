// aarch64 boot stage 2: higher-half entry/exit glue (MMU on, virtual VAs).
// Ported from the old kernel_entry.S.
//
// boot1_phys.zig branches to `enter_virtual_addressing` once the MMU is on, so
// this code runs in the higher half.

extern fn kmain() callconv(.c) noreturn;

// Linker-script symbols (see linker.ld). 16-byte aligned; only their addresses
// are used.
extern var __bss_start: u8;
extern var __bss_end: u8;

/// First code executed in the higher half. Switching the stack pointer must be
/// done in asm — changing SP inside a normal function would invalidate its
/// frame — so this is a naked trampoline that sets the virtual SP and tail-calls
/// init_arm.
///
/// x0 holds whatever the bootloader left at reset, threaded down through
/// boot1_phys -> enter_higher_half. We only touch x2/sp here, so it flows
/// straight into init_arm's first argument. On raspi3b that value is NOT the
/// DTB (see init_arm); on a generic armv8 board booted via EDK/EFI it will be.
export fn enter_virtual_addressing() callconv(.naked) noreturn {
    asm volatile (
        \\ adrp x2, __kernel_stack_top
        \\ add  x2, x2, #:lo12:__kernel_stack_top
        \\ msr  SPSel, #1            // switch to SP_EL1
        \\ mov  sp, x2
        \\ b    init_arm
    );
}

/// Runs on the virtual kernel stack: zero .bss, then hand off to the kernel.
/// `boot_x0` is the value x0 held at reset, threaded down from boot1_phys.
export fn init_arm(boot_x0: usize) callconv(.c) noreturn {
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

    const uart = @import("io/uart.zig");
    uart.init();

    const kprint = @import("../../kprint.zig");

    // RASPI3B: the machine resets all cores to 0x0 and does NOT hand the DTB to
    // the kernel in x0 (boot_x0 is just leftover reset state), so the device
    // tree is loaded at a fixed physical address by build.zig's loader device
    // and we read it from there.
    //
    // TODO(generic-armv8): once we boot a generic armv8 board via the EDK/EFI
    // protocol, x0 *does* carry the DTB pointer — drop this override and use
    // boot_x0 directly (it is already threaded down from the reset entry).
    _ = boot_x0;
    const fdt_phys: usize = 0x3000000; // must match build.zig loader addr

    // Sanity-check the blob: an FDT starts with the big-endian magic 0xd00dfeed.
    // fdt_phys is a *physical* address; read it through the higher-half map
    // (PA + kernel_va_base) rather than the low identity VA.
    const kernel_va_base: usize = 0xFFFF000000000000;
    const fdt_magic = @byteSwap(@as(*const u32, @ptrFromInt(fdt_phys + kernel_va_base)).*);
    kprint.write("FDT @ 0x{x} magic=0x{x}\r", .{ fdt_phys, fdt_magic });

    // Access our FDT
    //

    // Setup out proc0 structure
    // Setup our thread context
    // Setup uart console

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
