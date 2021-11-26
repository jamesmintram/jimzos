const std = @import("std");
const builtin = @import("std").builtin;
const kprint = @import("kprint.zig");

const kernel_elf = @import("kernel_elf.zig");

var kernel_panic_allocator_bytes: [5 * 1024 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = &kernel_panic_allocator_state.allocator;

fn display_info(dwarf_info: *std.dwarf.DwarfInfo) void {

    std.dwarf.openDwarfDebugInfo(dwarf_info, kernel_panic_allocator) catch {};

    for (dwarf_info.func_list.items) |func| {
        kprint.write("Function {s}\r", .{func.name});
    }

    kprint.write("DWARF loaded\r", .{});
}


fn extract_dwarf_info(kernel: *kernel_elf.KernelElf) !std.dwarf.DwarfInfo {
    var section_headers_arr: [64]std.elf.Elf64_Shdr = undefined;
    var section_headers = section_headers_arr[0..kernel.header.shnum];

    // Build array of section headers
    var idx:u32 = 0;
    var section_headers_iter = kernel.header.section_header_iterator(&kernel.stream);
    
    while (try section_headers_iter.next()) |section| {
        section_headers[idx] = section;
        idx += 1;
    }
    
    const sh_string_table = section_headers[kernel.header.shstrndx];    
    var str_table_slice = kernel.data[sh_string_table.sh_offset..(sh_string_table.sh_offset + sh_string_table.sh_size)];

    kprint.write("Enum sections {}\r", .{str_table_slice.len});

    var debug_info: []const u8 = undefined;
    var debug_str: []const u8 = undefined;
    var debug_line: []const u8 = undefined;
    var debug_ranges: []const u8 = undefined;
    var debug_abbrev: []const u8 = undefined;

    for (section_headers) |section| {
        var sh_name_str = std.mem.span(@ptrCast([*:0]u8, &str_table_slice[section.sh_name]));

        if ( std.mem.eql(u8, sh_name_str, ".debug_info")) {
            debug_info = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if ( std.mem.eql(u8, sh_name_str, ".debug_str")) {
            debug_str = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if ( std.mem.eql(u8, sh_name_str, ".debug_line")) {
            debug_line = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if ( std.mem.eql(u8, sh_name_str, ".debug_ranges")) {
            debug_ranges = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if ( std.mem.eql(u8, sh_name_str, ".debug_abbrev")) {
            debug_abbrev = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }               
    }

    //FIXME How to check we have found everything we need?
    
    return std.dwarf.DwarfInfo{
        .endian = std.builtin.Endian.Little,
        .debug_info = debug_info,
        .debug_abbrev = debug_abbrev,
        .debug_str = debug_str,
        .debug_line = debug_line,
        .debug_ranges = debug_ranges,
    };
}

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

    var debug_info = extract_dwarf_info(kernel_elf.get()) catch unreachable;
    _ = debug_info;

    display_info(&debug_info);

    while (true) {}
}
