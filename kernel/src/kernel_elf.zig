const std = @import("std");

pub const KernelElf = struct {
    stream: std.io.FixedBufferStream([]u8),
    header: std.elf.Header,
    data: [*]u8,

    fn load() !KernelElf {
        const va_base = 0xFFFF000000000000;
        const elf_address = 0x1000000 + va_base;
        const elf_size = 0x100000; //Fixme 4MB fixed size is hacky

        const elf_start_ptr = @intToPtr([*]u8, elf_address);
        const elf_slice = elf_start_ptr[0..elf_size];

        var stream = std.io.fixedBufferStream(elf_slice);
        var header = try std.elf.Header.read(&stream);

        return KernelElf{
            .stream = stream,
            .header = header,
            .data = elf_start_ptr
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
