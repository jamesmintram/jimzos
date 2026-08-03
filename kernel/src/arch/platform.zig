//! Statically selected machine-platform boundary.
//!
//! Machine-independent initialization enters here to configure devices after
//! architecture bootstrap has made normal memory and bus services available.

const builtin = @import("builtin");

const implementation = switch (builtin.cpu.arch) {
    .aarch64 => @import("aarch64/platform.zig"),
    else => @compileError("unsupported CPU architecture"),
};

pub const configureDevices = implementation.configureDevices;
