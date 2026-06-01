const regs = @import("../types/regs.zig");

const mmio = @import("mmio.zig");

const Register = regs.Register;

pub const GPFSEL0 = @as(u32, mmio.MMIO_BASE + 0x00200000);
pub const GPFSEL1 = Register { .ReadWrite = mmio.MMIO_BASE + 0x00200004 };
pub const GPFSEL2 = @as(u32, mmio.MMIO_BASE + 0x00200008);
pub const GPFSEL3 = @as(u32, mmio.MMIO_BASE + 0x0020000C);
pub const GPFSEL4 = @as(u32, mmio.MMIO_BASE + 0x00200010);
pub const GPFSEL5 = @as(u32, mmio.MMIO_BASE + 0x00200014);
pub const GPSET0 = @as(u32, mmio.MMIO_BASE + 0x0020001C);
pub const GPSET1 = @as(u32, mmio.MMIO_BASE + 0x00200020);
pub const GPCLR0 = @as(u32, mmio.MMIO_BASE + 0x00200028);
pub const GPLEV0 = @as(u32, mmio.MMIO_BASE + 0x00200034);
pub const GPLEV1 = @as(u32, mmio.MMIO_BASE + 0x00200038);
pub const GPEDS0 = @as(u32, mmio.MMIO_BASE + 0x00200040);
pub const GPEDS1 = @as(u32, mmio.MMIO_BASE + 0x00200044);
pub const GPHEN0 = @as(u32, mmio.MMIO_BASE + 0x00200064);
pub const GPHEN1 = @as(u32, mmio.MMIO_BASE + 0x00200068);
pub const GPPUD = Register { .WriteOnly = mmio.MMIO_BASE + 0x00200094 };
pub const GPPUDCLK0 = Register { .WriteOnly = mmio.MMIO_BASE + 0x00200098 };
pub const GPPUDCLK1 = @as(u32, mmio.MMIO_BASE + 0x0020009C);
