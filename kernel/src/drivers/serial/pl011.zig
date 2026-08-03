const std = @import("std");
const console = @import("../../console.zig");
const MmioRegion = @import("../../io/mmio_region.zig").MmioRegion;

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

pub const Config = struct {
    registers: MmioRegion,
    clock_hz: u32,
    baud: u32,
};

pub const Pl011 = struct {
    config: Config,

    const console_vtable: console.Device.VTable = .{
        .put = consolePut,
        .get = consoleGet,
    };

    pub fn create(config: Config) Pl011 {
        return .{ .config = config };
    }

    /// Replace the bootstrap mapping with the live bus mapping without
    /// reconfiguring the active UART or changing the console object's address.
    pub fn rebind(self: *Pl011, config: Config) !void {
        if (!self.config.registers.samePhysicalRange(config.registers)) {
            return error.ConsoleMismatch;
        }
        self.config = config;
    }

    pub fn configure(self: *Pl011) !void {
        if (self.config.baud == 0) return error.InvalidBaud;
        if (self.config.registers.size() < interrupt_clear_register + @sizeOf(u32)) {
            return error.InvalidRegisterRegion;
        }

        // PL011's combined 64ths divisor is round(UARTCLK * 4 / baud).
        const scaled_divisor = (@as(u64, self.config.clock_hz) * 4 + self.config.baud / 2) / self.config.baud;
        const integer_divisor = scaled_divisor / 64;
        const fractional_divisor = scaled_divisor % 64;
        if (integer_divisor == 0 or integer_divisor > std.math.maxInt(u16)) {
            return error.InvalidClock;
        }

        self.config.registers.write32(control_register, 0);
        self.config.registers.write32(interrupt_mask_register, 0);
        self.config.registers.write32(interrupt_clear_register, 0x7ff);
        self.config.registers.write32(integer_baud_register, @intCast(integer_divisor));
        self.config.registers.write32(fractional_baud_register, @intCast(fractional_divisor));
        self.config.registers.write32(line_control_register, line_control_word_length_8 | line_control_fifo_enable);
        self.config.registers.write32(control_register, control_uart_enable | control_transmit_enable | control_receive_enable);
    }

    pub fn asConsole(self: *Pl011) console.Device {
        return .{
            .context = self,
            .vtable = &console_vtable,
        };
    }

    pub fn installAsConsole(self: *Pl011) void {
        self.asConsole().install();
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
        while ((self.config.registers.read32(flag_register) & flag_receive_empty) != 0) {}
        return @truncate(self.config.registers.read32(data_register));
    }

    fn putRaw(self: *Pl011, byte: u8) void {
        while ((self.config.registers.read32(flag_register) & flag_transmit_full) != 0) {}
        self.config.registers.write32(data_register, byte);
    }

    fn consolePut(context: *anyopaque, byte: u8) void {
        const self: *Pl011 = @ptrCast(@alignCast(context));
        self.put(byte);
    }

    fn consoleGet(context: *anyopaque) u8 {
        const self: *Pl011 = @ptrCast(@alignCast(context));
        return self.get();
    }
};
