const std = @import("std");
const BufferStream = @import("buffer_stream.zig").BufferStream;

pub const KernelElf = struct {
    stream: BufferStream,
    header: std.elf.Header,
    data: []u8,

    fn load() !KernelElf {
        const va_base = 0xFFFF000000000000;
        const elf_address = 0x1000000 + va_base;
        const elf_size = 0x100000; //Fixme 4MB fixed size is hacky

        const elf_start_ptr: [*]u8 = @ptrFromInt(elf_address);
        const elf_slice = elf_start_ptr[0..elf_size];

        var stream = BufferStream.init(elf_slice);
        const header = try std.elf.Header.read(stream.ioReader());

        return KernelElf{
            .stream = stream,
            .header = header,
            .data = elf_slice,
        };
    }
};

var kernel_elf : KernelElf = undefined;

pub fn init() !void {
    kernel_elf = try KernelElf.load();
}

pub fn get() *KernelElf {
    return &kernel_elf;
}
