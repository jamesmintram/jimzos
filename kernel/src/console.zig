const std = @import("std");
const Pl011 = @import("drivers/serial/pl011.zig").Pl011;

const Backend = struct {
    context: *anyopaque,
    put: *const fn (*anyopaque, u8) void,
};

var active_backend: ?Backend = null;
var output_buffer: [256]u8 = undefined;
var output_writer = std.Io.Writer{
    .vtable = &.{ .drain = drain },
    .buffer = &output_buffer,
};

pub fn attachPl011(device: *Pl011) void {
    active_backend = .{
        .context = device,
        .put = pl011Put,
    };
}

pub fn write(comptime format: []const u8, args: anytype) void {
    if (active_backend == null) return;
    output_writer.print(format, args) catch {};
    output_writer.flush() catch {};
}

fn pl011Put(context: *anyopaque, byte: u8) void {
    const device: *Pl011 = @ptrCast(@alignCast(context));
    device.put(byte);
}

fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    writeBytes(writer.buffer[0..writer.end]);
    writer.end = 0;

    var written: usize = 0;
    for (data[0 .. data.len - 1]) |bytes| {
        writeBytes(bytes);
        written += bytes.len;
    }

    const pattern = data[data.len - 1];
    for (0..splat) |_| writeBytes(pattern);
    return written + pattern.len * splat;
}

fn writeBytes(bytes: []const u8) void {
    const backend = active_backend orelse return;
    for (bytes) |byte| backend.put(backend.context, byte);
}
