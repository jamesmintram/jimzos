const std = @import("std");

/// Minimal random-access stream over a fixed in-memory buffer.
///
/// Replaces the removed `std.io.FixedBufferStream`. The std I/O rework
/// ("Writergate") collapsed the old `reader()` / `seekableStream()` helpers
/// into the new `std.Io.Reader`, which is forward-only by default. The ext2
/// parser and the ELF loader both need random access, so we keep the small
/// surface they rely on (`reader().readNoEof` / `seekableStream().seekTo`) and
/// implement seeking by moving the underlying reader's `seek` cursor directly
/// (valid because a fixed reader keeps the whole buffer resident).
pub const BufferStream = struct {
    inner: std.Io.Reader,

    pub fn init(buffer: []const u8) BufferStream {
        return .{ .inner = std.Io.Reader.fixed(buffer) };
    }

    /// The underlying `std.Io.Reader`, e.g. for `std.elf.Header.read`.
    pub fn ioReader(self: *BufferStream) *std.Io.Reader {
        return &self.inner;
    }

    // ext2 calls `parse_source.reader()` / `.seekableStream()` and then
    // `.readNoEof()` / `.seekTo()`. Both accessors return self so the shared
    // seek cursor stays consistent.
    pub fn reader(self: *BufferStream) *BufferStream {
        return self;
    }

    pub fn seekableStream(self: *BufferStream) *BufferStream {
        return self;
    }

    pub fn seekTo(self: *BufferStream, pos: u64) !void {
        const p: usize = @intCast(pos);
        if (p > self.inner.end) return error.EndOfStream;
        self.inner.seek = p;
    }

    pub fn readNoEof(self: *BufferStream, buf: []u8) !void {
        try self.inner.readSliceAll(buf);
    }
};
