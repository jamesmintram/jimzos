// const builtin = @import("builtin");
const kprint = @import("kprint.zig");
const util = @import("arch/aarch64/util.zig");
const arch_init = @import("arch/aarch64/arch_init.zig");
const std = @import("std");
const builtin = @import("std").builtin;

const debug = std.debug;
const assert = debug.assert;

const process = @import("proc.zig");
const thread = @import("thread.zig");

const mem = std.mem;
const Allocator = mem.Allocator;

// const BumpAllocator = @import("vm/page_frame_manager.zig").BumpAllocator;
const page = @import("vm/page.zig");

// Alloc/Free to work?
// Process ping pong
// Verifies that the adjusted length will still map to the full length
const vm = @import("vm.zig");

const KernelElf = struct {
    stream: std.io.FixedBufferStream([]u8),
    header: std.elf.Header,

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
        };
    }
};

fn enumerate_kernel(kernel: *KernelElf) !void {
    kprint.write("Enum sections\r", .{});
    var section_headers = kernel.header.section_header_iterator(&kernel.stream);

    while (section_headers.next() catch unreachable) |section| {
        kprint.write("{x:0>2}\r", .{section.sh_type});
    }

    kprint.write("Enum headers\r", .{});
    var program_headers = kernel.header.program_header_iterator(&kernel.stream);

    while (program_headers.next() catch unreachable) |phdr| {
        if (phdr.p_type == std.elf.PT_LOAD) {
            kprint.write("LMA 0x{x:0>16}  VMA 0x{x:0>16}\r", .{ phdr.p_paddr, phdr.p_vaddr });
        }
    }

    kprint.write("Complete\r", .{});
}

export fn kmain() noreturn {
    arch_init.init();
    vm.init();

    kprint.write("JimZOS v{s}\r", .{util.Version});

    // Get inside a thread context ASAP
    var init_thread = thread.create_initial_thread(&vm.get_page_frame_manager().allocator, kmain_init) catch unreachable;
    thread.switch_to_initial(init_thread);

    kprint.write("End of kmain\r", .{});
    unreachable;
}

fn kmain_init() noreturn {
    // framebuffer.init().?;
    // framebuffer.write("JimZOS v{}\r", .{util.Version});

    kprint.write("Entered init thread\r", .{});

    //TODO: Yield ping pong between EL1 and EL0
    //          - Copy a flat binary into the "Text" space
    //          - Handle EL0 sync exceptions
    //          - Switching address space
    //          - Pre-allocate some heap + stack space (Later we can on demand)

    var kernel = KernelElf.load() catch unreachable;
    enumerate_kernel(&kernel) catch unreachable;

    // Test our crash out here
    // var t : u8 = 10;
    // while(true) { t+=1;}

    // const total_memory = 1024 * 1024 * 1024; //1GB
    // const memory_start = 0x000000000038e000 + 0x1000000; //__heap_phys_start; FIXME - relocation error when using symbol
    // const available_memory = total_memory - memory_start;
    // const page_count = available_memory / 4096; // page_size = 4096

    // kprint.write("Pages\r", .{});
    // page.add_phys_pages(@intToPtr(*page.Page, memory_start), memory_start, page_count);
    // // page.dump(uart);

    // kprint.write("Create init thread\r", .{});
    // //TODO: Initialize the kernel bump allocator (which will just use the vm/page module)
    // var alt_thread = thread.create_initial_thread(&vm.get_page_frame_manager().allocator, kmain_alt) catch unreachable;

    // kprint.write("Swotcj\r", .{});
    // thread.switch_to(alt_thread);

    while (true) {
        // kprint.write("INIT\r", .{});
        // thread.yield();
        // const x = kprint.get();
        // kprint.put(x);
        // framebuffer.put(x);
    }
}

fn kmain_alt() noreturn {
    kprint.write("Entered alt thread\r", .{});

    while (true) {
        kprint.write("ALT\r", .{});
        thread.yield();
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @import("panic.zig").handle_panic(msg, error_return_trace);
}
