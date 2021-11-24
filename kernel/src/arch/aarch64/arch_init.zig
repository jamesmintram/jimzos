const uart = @import("io/uart.zig");

pub fn init() void{
    uart.init();   
}
