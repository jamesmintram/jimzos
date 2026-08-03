//! Statically selected CPU-operation boundary.

const builtin = @import("builtin");

const implementation = switch (builtin.cpu.arch) {
    .aarch64 => struct {
        pub const cpu = @import("aarch64/cpu.zig");
    },
    else => @compileError("unsupported CPU architecture"),
};

pub const cpu = implementation.cpu;
