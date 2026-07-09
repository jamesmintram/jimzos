const std = @import("std");

const data_register = 0x000;
const flag_register = 0x018;
const integer_baud_register = 0x024;
const fractional_baud_register = 0x028;
const line_control_register = 0x02c;
const control_register = 0x030;
const interrupt_mask_register = 0x038;
const interrupt_clear_register = 0x044;

const flag_receive_empty = 1 << 4;
const flag_transmit_full = 1 << 5;
const line_control_fifo_enable = 1 << 4;
const line_control_word_length_8 = 0b11 << 5;
const control_uart_enable = 1 << 0;
const control_transmit_enable = 1 << 8;
const control_receive_enable = 1 << 9;

inline fn barrier() void {
    asm volatile ("dmb sy" ::: .{ .memory = true });
}

pub const Config = struct {
    physical_base: usize,
    region_size: usize,
    clock_hz: u32,
    baud: u32,
};

pub const Pl011 = struct {
    config: Config,

    pub fn create(config: Config) Pl011 {
        return .{ .config = config };
    }

    /// Take ownership of an already configured early console without touching
    /// its registers, so output remains uninterrupted during driver attach.
    pub fn adopt(early: *const Pl011, config: Config) !Pl011 {
        if (early.config.physical_base != config.physical_base) {
            return error.ConsoleMismatch;
        }

        return .{ .config = config };
    }

    pub fn configure(self: *Pl011) !void {
        if (self.config.baud == 0) return error.InvalidBaud;
        if (self.config.region_size < interrupt_clear_register + @sizeOf(u32)) {
            return error.InvalidRegisterRegion;
        }

        // PL011's combined 64ths divisor is round(UARTCLK * 4 / baud).
        const scaled_divisor = (@as(u64, self.config.clock_hz) * 4 + self.config.baud / 2) / self.config.baud;
        const integer_divisor = scaled_divisor / 64;
        const fractional_divisor = scaled_divisor % 64;
        if (integer_divisor == 0 or integer_divisor > std.math.maxInt(u16)) {
            return error.InvalidClock;
        }

        self.write(control_register, 0);
        self.write(interrupt_mask_register, 0);
        self.write(interrupt_clear_register, 0x7ff);
        self.write(integer_baud_register, @intCast(integer_divisor));
        self.write(fractional_baud_register, @intCast(fractional_divisor));
        self.write(line_control_register, line_control_word_length_8 | line_control_fifo_enable);
        self.write(control_register, control_uart_enable | control_transmit_enable | control_receive_enable);
    }

    pub fn put(self: *Pl011, byte: u8) void {
        if (byte == '\n' or byte == '\r') {
            self.putRaw('\r');
            self.putRaw('\n');
            return;
        }
        self.putRaw(byte);
    }

    pub fn get(self: *Pl011) u8 {
        while ((self.read(flag_register) & flag_receive_empty) != 0) {}
        return @truncate(self.read(data_register));
    }

    fn putRaw(self: *Pl011, byte: u8) void {
        while ((self.read(flag_register) & flag_transmit_full) != 0) {}
        self.write(data_register, byte);
    }

    fn write(self: *const Pl011, offset: usize, value: u32) void {
        barrier();
        @as(*volatile u32, @ptrFromInt(self.config.physical_base + offset)).* = value;
    }

    fn read(self: *const Pl011, offset: usize) u32 {
        barrier();
        return @as(*volatile u32, @ptrFromInt(self.config.physical_base + offset)).*;
    }
};
