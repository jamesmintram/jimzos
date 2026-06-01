const builtin = @import("std").builtin;
const kprint = @import("kprint.zig");

// NOTE: Source-line symbolization used to walk the kernel ELF's DWARF info via
// `std.dwarf.DwarfInfo` (openDwarfDebugInfo / findCompileUnit /
// getLineNumberInfo). That high-level parser was removed from std; DWARF now
// lives in `std.debug.Dwarf` behind a very different, allocator-heavy API that
// is awkward to drive from a freestanding kernel. Until that is re-ported we
// print raw return addresses instead. Resolve them offline against
// zig-out/bin/kernel8.elf, e.g.:
//
//     llvm-symbolizer --obj=zig-out/bin/kernel8.elf <address>
//     addr2line -e zig-out/bin/kernel8.elf -f <address>
//
// TODO: re-implement symbolized backtraces on top of `std.debug.Dwarf`.

var already_panicking: bool = false;

extern fn exit() noreturn;

pub fn handlePanic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    if (already_panicking) {
        kprint.write("Double panic\r", .{});
        while (true) {}
    }
    already_panicking = true;

    printGuru(msg);

    if (error_return_trace) |stack_trace| {
        dumpStackTrace(stack_trace);
    } else {
        kprint.write("No stack trace available\r", .{});
    }

    exit();
}

fn dumpStackTrace(stack_trace: *builtin.StackTrace) void {
    kprint.write("Stack trace (raw return addresses):\r", .{});

    var frame_index: usize = 0;
    var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frame_index];
        kprint.write("  0x{x:0>16}\r", .{return_address});
    }
}

pub fn printGuru(msg: []const u8) void {
    kprint.write("+=================+\r", .{});
    kprint.write("| GURU MEDITATION |\r", .{});
    kprint.write("+=================+\r", .{});
    kprint.write("\r", .{});
    kprint.write("Message: {s}\r", .{msg});
    kprint.write("\r", .{});
}

pub fn printAddress(address: u64) !void {
    kprint.write("0x{x:0>16} (symbolize against kernel8.elf)\r", .{address});
}
