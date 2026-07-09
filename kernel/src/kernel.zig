// const builtin = @import("builtin");
const kprint = @import("kprint.zig");
const std = @import("std");
const builtin = @import("std").builtin;

const debug = std.debug;
const assert = debug.assert;

const process = @import("proc.zig");
const thread = @import("thread.zig");

const mem = std.mem;
const Allocator = mem.Allocator;

// Alloc/Free to work?
// Process ping pong
// Verifies that the adjusted length will still map to the full length
const vm = @import("vm.zig");
const kernel_elf = @import("kernel_elf.zig");
const ext2 = @import("ext2");
const buffer_stream = @import("buffer_stream.zig");
const build_options = @import("build_options");
const BootInfo = @import("boot/boot_info.zig").BootInfo;

// Force the arch entry/exit glue (enter_virtual_addressing, exit) to be
// compiled so its `export fn`s are emitted into the image.
comptime {
    _ = @import("arch/aarch64/boot2_virt.zig");
}

export fn kmain(boot_info: *const BootInfo) noreturn {
    kernel_elf.init() catch unreachable;

    kprint.write("JimZOS v0.1.1 ({} described CPUs)\r", .{boot_info.cpus.len});
    const allocator_stats = vm.get_page_frame_manager().stats();
    kprint.write("allocator: {} usable pages, {} free\r", .{
        allocator_stats.usable_pages,
        allocator_stats.free_pages,
    });

    //test_crashes();

    // Get inside a thread context ASAP
    var allocator = vm.get_page_frame_manager().allocator();
    const allocator_probe = allocator.alloc(u8, 4097) catch unreachable;
    @memset(allocator_probe, 0xa5);
    allocator.free(allocator_probe);
    const init_thread = thread.create_initial_thread(&allocator, kmainInit) catch unreachable;
    thread.switch_to_initial(init_thread);

    kprint.write("End of kmain\r", .{});
    unreachable;
}

fn kmainInit() noreturn {
    // framebuffer.init().?;

    kprint.write("Entered init thread\r", .{});

    //TODO: Yield ping pong between EL1 and EL0
    //          - Copy a flat binary into the "Text" space
    //          - Handle EL0 sync exceptions
    //          - Switching address space
    //          - Pre-allocate some heap + stack space (Later we can on demand)

    // testCrashes();

    // kprint.write("Create init thread\r", .{});
    // var alt_thread = thread.create_initial_thread(&vm.get_page_frame_manager().allocator, kmainAlt) catch unreachable;

    // kprint.write("Swotcj\r", .{});
    // thread.switch_to(alt_thread);

    const img_address = build_options.ext2_phys + 0xFFFF000000000000;
    const img_size = build_options.ext2_used_size;

    const img_start_ptr: [*]u8 = @ptrFromInt(img_address);
    const img_slice = img_start_ptr[0..img_size];

    var img_stream = buffer_stream.BufferStream.init(img_slice);

    const fs = ext2.FS.mount(&img_stream) catch unreachable;
    const super_block = fs.superblock(&img_stream) catch unreachable;

    kprint.write("FS Info:\r", .{});
    kprint.write("\tMagic                  0x{X}\r", .{super_block.s_magic});
    kprint.write("\tNumber of block groups {}\r", .{super_block.block_group_count()});
    kprint.write("\tBlock size             {}\r", .{super_block.block_size()});

    kprint.write("\ts_blocks_count         {}\r", .{super_block.s_blocks_count});
    kprint.write("\ts_first_data_block     {}\r", .{super_block.s_first_data_block});
    kprint.write("\ts_blocks_per_group     {}\r", .{super_block.s_blocks_per_group});

    exit();

    while (true) {
        // kprint.write("INIT\r", .{});
        // thread.yield();
        // const x = kprint.get();
        // kprint.put(x);
        // framebuffer.put(x);
    }
}

fn kmainAlt() noreturn {
    kprint.write("Entered alt thread\r", .{});

    while (true) {
        kprint.write("ALT\r", .{});
        thread.yield();
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, size: ?usize) noreturn {
    _ = size;

    @import("panic.zig").handlePanic(msg, error_return_trace);
}

extern fn exit() noreturn;

export fn exception_panic(esr_el1: u64, elr_el1: u64, spsr_el1: u64, far_el1: u64) noreturn {
    @import("panic.zig").printGuru("Unhandled synchronous exception triggered");

    kprint.write("esr_el1:  0x{x:0>16}\r", .{esr_el1});
    kprint.write("spsr_el1: 0x{x:0>16}\r", .{spsr_el1});
    kprint.write("far_el1:  0x{x:0>16}\r", .{far_el1});

    // elr_el1 should contain an address to a source code location, lets
    // try to print it.
    kprint.write("elr_el1:  ", .{});
    @import("panic.zig").printAddress(elr_el1) catch unreachable;

    exit();
}

fn testCrashes() void {
    // const fn someCrash2 () !void {
    //     return error.Err;
    // }

    // const fn someCrash () !void {
    //     try someCrash2();
    // }

    //some_crash() catch @panic("Oh bum");
    // var ptr : *u8 = @intToPtr(*u8, 0xFFFFFFFFFFFFFFFF);
    // ptr.* = 2;
}
