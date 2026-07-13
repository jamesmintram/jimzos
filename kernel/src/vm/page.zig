//! Kernel-wide base-page contract.
//!
//! The VM layer works in 4 KiB base pages. Architecture page-table code must
//! validate its configured translation granule against this definition rather
//! than defining a second page size.

pub const shift: u6 = 12;
pub const size: u64 = @as(u64, 1) << shift;
pub const mask: u64 = size - 1;

comptime {
    if (size != 4096) @compileError("JimZOS currently requires 4 KiB base pages");
}
