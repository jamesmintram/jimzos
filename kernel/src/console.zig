const std = @import("std");

pub const Device = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        put: *const fn (*anyopaque, u8) void,
        get: ?*const fn (*anyopaque) u8 = null,
    };

    pub fn install(self: Device) void {
        active_device = self;
    }

    fn put(self: Device, byte: u8) void {
        self.vtable.put(self.context, byte);
    }

    fn get(self: Device) ?u8 {
        const read_byte = self.vtable.get orelse return null;
        return read_byte(self.context);
    }
};

var active_device: ?Device = null;
var output_buffer: [256]u8 = undefined;
var output_writer = std.Io.Writer{
    .vtable = &.{ .drain = drain },
    .buffer = &output_buffer,
};

pub fn write(comptime format: []const u8, args: anytype) void {
    if (active_device == null) return;
    output_writer.print(format, args) catch {};
    output_writer.flush() catch {};
}

pub fn read() ?u8 {
    const device = active_device orelse return null;
    return device.get();
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
    const device = active_device orelse return;
    for (bytes) |byte| device.put(byte);
}
