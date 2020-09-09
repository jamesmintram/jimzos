const std = @import("std");
const io = @import("../io.zig");
const types = @import("../types.zig");

const mmio = io.mmio;
const gpio = io.gpio;
const mbox = io.mbox;

const Register = types.regs.Register;
const NoError = types.errorTypes.NoError;

// See page 90 of the BCM2835 manual for information about most of these.

// Constants for UART0 addresses.
const UART_DR = Register { .ReadWrite = mmio.MMIO_BASE + 0x00201000 };
const UART_FR = Register { .ReadOnly = mmio.MMIO_BASE + 0x00201018 };
const UART_IBRD = Register { .WriteOnly = mmio.MMIO_BASE + 0x00201024 };
const UART_FBRD = Register { .WriteOnly = mmio.MMIO_BASE + 0x00201028 };
const UART_LCRH = Register { .WriteOnly = mmio.MMIO_BASE + 0x0020102C };
const UART_CR = Register { .WriteOnly = mmio.MMIO_BASE + 0x00201030 };
const UART_IMSC = Register { .ReadOnly = mmio.MMIO_BASE + 0x00201038 };
const UART_ICR = Register { .WriteOnly = mmio.MMIO_BASE + 0x00201044 };

pub fn init() void {
    // Temporarily disable UART0 for config
    mmio.write(UART_CR, 0).?;
    // Setup clock mailbox call
    mbox.mbox[0] = 9*4;
    mbox.mbox[1] = mbox.MBOX_REQUEST;
    mbox.mbox[2] = mbox.MBOX_TAG_SETCLKRATE;
    mbox.mbox[3] = 12;
    mbox.mbox[4] = 8;
    mbox.mbox[5] = 2;
    mbox.mbox[6] = 4000000;
    mbox.mbox[7] = 0;
    mbox.mbox[8] = mbox.MBOX_TAG_LAST;
    mbox.mboxCall(mbox.MBOX_CH_PROP).?;

    var r: u32 = mmio.read(gpio.GPFSEL1).?;
    // Clean gpio pins 14 and 15
    const val : u32 =((7 << 12) | (7 << 15));

    r &=~val;
    // Set alt0 for pins 14 and 15. alt0 functionality on these pins is Tx/Rx
    // respectively for UART0. Note that alt5 on these pins is Tx/Rx for UART1.
    r |= (4 << 12) | (4 << 15);
    mmio.write(gpio.GPFSEL1, r).?;
    // Write zero to GPPUD to set the pull up/down state to 'neither'
    mmio.write(gpio.GPPUD, 0).?;
    mmio.wait(150);
    // Mark the pins that are going to be modified by writing them into GPPUDCLK0
    // This makes sure that only pins 14 and 15 are set to the 'neither' state.
    mmio.write(gpio.GPPUDCLK0, (1 << 14) | (1 << 15)).?;
    mmio.wait(150);
    // Remove above clock for any future GPPUDCLK0 operations so they don't get
    // the wrong pins to modify
    mmio.write(gpio.GPPUDCLK0, 0).?;
    // Clear interrupts
    mmio.write(UART_ICR, 0x7FF).?;
    // 115200 baud
    mmio.write(UART_IBRD, 2).?;
    mmio.write(UART_FBRD, 0xB).?;
    mmio.write(UART_LCRH, 0b11 << 15).?;
    mmio.write(UART_CR, 0x301).?;
}

pub fn put(c: u8) void {
    while ((mmio.read(UART_FR).? & 0x20) != 0) {}
    switch (c) {
        '\n' => {
            mmio.write(UART_DR, '\n').?;
            mmio.write(UART_DR, '\r').?;
        },
        '\r' => {
            mmio.write(UART_DR, '\n').?;
            mmio.write(UART_DR, '\r').?;
            for ("READY:> ") |d|
                put(d);
        },
        else => {
            mmio.write(UART_DR, c).?;
        }
    }
}

pub fn get() u8 {
    while ((mmio.read(UART_FR).? & 0x10) != 0) {}
    return @truncate(u8, mmio.read(UART_DR).?);
}

pub fn writeBytes(data: []const u8) void {
    for (data) |c| {
        put(c);
    }
}

/// `writeHandler` handles write requests for UART0 from `write`.
fn writeHandler(context: void, data: []const u8) NoError!void {
    writeBytes(data);
}

/// `write` manages all writes for UART0. It takes formatted arguments, in the
/// same manner that `std.debug.warn()` does. It then passes them to `writeHandler`
/// for writing out.
// pub fn write(comptime data: []const u8, args: ...) void {
//     std.fmt.format({}, NoError, writeHandler, data, args) catch |e| switch (e) {};
// }
