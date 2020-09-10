// const builtin = @import("builtin");
const io = @import("io.zig");
const vga = @import("vga.zig");
const uart = io.uart;
const util = @import("util.zig");
const framebuffer = vga.framebuffer;

// const emmc = io.emmc;

export fn kmain() noreturn {
    uart.init();
    uart.write("JimZOS v{}\r", .{util.Version});

    framebuffer.init().?;  
    framebuffer.write("JimZOS v{}\r", .{util.Version});
    
    while (true) {
        const x = uart.get();
        uart.put(x);
        framebuffer.put(x);
    }
    // // enter low power state and hang if we get somehow get out of the while loop.
    // util.powerOff();
    // util.hang();
}