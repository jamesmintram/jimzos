const regs = @import("../types/regs.zig");

const Register = regs.Register;

/// Full-system data memory barrier that orders MMIO accesses on real hardware.
inline fn barrier() void {
    asm volatile ("dmb sy" ::: .{ .memory = true });
}

/// Base address for the MMIO operations.
pub const MMIO_BASE: u32 = 0x3F000000;

// TODO: Make register arguments comptime values so invalid access modes are
// compile errors and these APIs do not need optional return values.

/// Write data to a given MMIO register, returning null
/// if the register had an incorrect type.
pub fn write(reg: Register, data: u32) ?void {
    barrier();
    switch (reg) {
        Register.ReadOnly => return null,
        Register.WriteOnly => {
            @as(*volatile u32, @ptrFromInt(reg.WriteOnly)).* = data;
        },
        Register.ReadWrite => {
            @as(*volatile u32, @ptrFromInt(reg.ReadWrite)).* = data;
        },
    }
}

/// Read data to a given MMIO register, returning null.
/// if the register had an incorrect type.
pub fn read(reg: Register) ?u32 {
    barrier();
    switch (reg) {
        Register.WriteOnly => return null,
        Register.ReadOnly => {
            return @as(*volatile u32, @ptrFromInt(reg.ReadOnly)).*;
        },
        Register.ReadWrite => {
            return @as(*volatile u32, @ptrFromInt(reg.ReadWrite)).*;
        },
    }
}

/// Stall the CPU for a given number of cycles.
pub fn wait(count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        // Marked as volatile so the optimizer doesn't optimize it away
        asm volatile ("mov w0, w0");
    }
}
