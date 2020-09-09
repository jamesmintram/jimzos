// const builtin = @import("builtin");
const io = @import("io.zig");
const vga = @import("vga.zig");
const uart = io.uart;
// const util = @import("util.zig");
// const emmc = io.emmc;
const framebuffer = vga.framebuffer;

// const Version = util.Version;

export fn kmain() noreturn {
    uart.init();
    // uart.write("trOS v{}\r", Version);

    framebuffer.init().?;

    while (true)
    {
        
    }

    
    // framebuffer.write("trOS v{}\r", Version);
    // while (true) {
    //     const x = uart.get();
    //     uart.put(x);
    //     framebuffer.put(x);
    // }
    // // enter low power state and hang if we get somehow get out of the while loop.
    // util.powerOff();
    // util.hang();
}