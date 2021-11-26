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
const kernel_elf = @import("kernel_elf.zig");

fn someCrash2() !void {
    return error.Err;
}

fn someCrash() !void {
    try someCrash2();
}

export fn kmain() noreturn {
    arch_init.init();
    kernel_elf.init() catch unreachable;
    vm.init();

    kprint.write("JimZOS v{s}\r", .{util.Version});

    //some_crash() catch @panic("Oh bum");

    var ptr : *u8 = @intToPtr(*u8, 0xFFFFFFFFFFFFFFFF);
    ptr.* = 2;

    // Get inside a thread context ASAP
    var init_thread = thread.create_initial_thread(&vm.get_page_frame_manager().allocator, kmainInit) catch unreachable;
    thread.switch_to_initial(init_thread);

    kprint.write("End of kmain\r", .{});
    unreachable;
}

fn kmainInit() noreturn {
    // framebuffer.init().?;
    // framebuffer.write("JimZOS v{}\r", .{util.Version});

    kprint.write("Entered init thread\r", .{});

    //TODO: Yield ping pong between EL1 and EL0
    //          - Copy a flat binary into the "Text" space
    //          - Handle EL0 sync exceptions
    //          - Switching address space
    //          - Pre-allocate some heap + stack space (Later we can on demand)

    // Test our crash out here

    // const total_memory = 1024 * 1024 * 1024; //1GB
    // const memory_start = 0x000000000038e000 + 0x1000000; //__heap_phys_start; FIXME - relocation error when using symbol
    // const available_memory = total_memory - memory_start;
    // const page_count = available_memory / 4096; // page_size = 4096

    // kprint.write("Pages\r", .{});
    // page.add_phys_pages(@intToPtr(*page.Page, memory_start), memory_start, page_count);
    // // page.dump(uart);

    // kprint.write("Create init thread\r", .{});
    // //TODO: Initialize the kernel bump allocator (which will just use the vm/page module)
    // var alt_thread = thread.create_initial_thread(&vm.get_page_frame_manager().allocator, kmainAlt) catch unreachable;

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

fn kmainAlt() noreturn {
    kprint.write("Entered alt thread\r", .{});

    while (true) {
        kprint.write("ALT\r", .{});
        thread.yield();
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @import("panic.zig").handlePanic(msg, error_return_trace);
}

export fn exception_panic(esr_el1: u64, elr_el1: u64, spsr_el1: u64, far_el1: u64) noreturn {
    
    @import("panic.zig").printGuru("Unhandled synchronous exception triggered");
    
    kprint.write("esr_el1:  0x{x:0>16}\r", .{esr_el1});
    kprint.write("spsr_el1: 0x{x:0>16}\r", .{spsr_el1});
    kprint.write("far_el1:  0x{x:0>16}\r", .{far_el1});

    // elr_el1 should contain an address to a source code location, lets
    // try to print it.
    kprint.write("elr_el1:  ", .{});
    @import("panic.zig").printAddress(elr_el1) catch unreachable;

    while(true) {}
}