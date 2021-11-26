const std = @import("std");
const builtin = @import("std").builtin;
const kprint = @import("kprint.zig");

var kernel_panic_allocator_bytes: [5 * 1024 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = &kernel_panic_allocator_state.allocator;

// fn getSelfDebugInfo() void { //} !*std.dwarf.DwarfInfo {
//     const S = struct {
//         var di: std.dwarf.DwarfInfo = undefined;
//     };

//     S.di = std.dwarf.DwarfInfo{
//         .endian = std.builtin.Endian.Little,
//         .debug_info = __debug_info_start,
//         .debug_abbrev = __debug_abbrev_start,
//         .debug_str = __debug_str_start,
//         .debug_line = __debug_line_start,
//         .debug_ranges = __debug_ranges_start,
//     };

//     kprint.write("Load up the DWARF {}\r", .{&__debug_info_end});
//     std.dwarf.openDwarfDebugInfo(&S.di, kernel_panic_allocator) catch {};

//     for (S.di.func_list.items) |_| {
//         kprint.write("Function\r", .{});
//     }
//     for (S.di.compile_unit_list.items) |_| {
//         kprint.write("Compile unit\r", .{});
//     }

//     kprint.write("DWARF loaded\r", .{});
//     //return &S.di;
// }

var already_panicking: bool = false;

pub fn handle_panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    _ = error_return_trace;

    if (already_panicking) {
        kprint.write("Double panick\r", .{});
        while (true) {}
    }
    already_panicking = true;

    kprint.write("+=================+\r", .{});
    kprint.write("| GURU MEDITATION |\r", .{});
    kprint.write("+=================+\r", .{});
    kprint.write("\r", .{});
    kprint.write("{s}\r", .{msg});

    // getSelfDebugInfo();

    while (true) {}
}
