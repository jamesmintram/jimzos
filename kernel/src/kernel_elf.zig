const std = @import("std");
const mmu = @import("arch/mmu.zig");
const BufferStream = @import("buffer_stream.zig").BufferStream;
const build_options = @import("build_options");

pub const KernelElf = struct {
    stream: BufferStream,
    header: std.elf.Header,
    data: []u8,

    fn load() !KernelElf {
        const elf_address = try mmu.physicalToVirtual(build_options.kernel_elf_phys);
        const elf_size = build_options.kernel_elf_reserved_size;

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

var kernel_elf: KernelElf = undefined;

pub fn init() !void {
    kernel_elf = try KernelElf.load();
}

pub fn get() *KernelElf {
    return &kernel_elf;
}
