const std = @import("std");
const builtin = @import("std").builtin;
const kprint = @import("kprint.zig");

const kernel_elf = @import("kernel_elf.zig");

var kernel_panic_allocator_bytes: [5 * 1024 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = kernel_panic_allocator_state.allocator();

fn dumpStackTrace(dwarf_info: *std.dwarf.DwarfInfo, stack_trace: *builtin.StackTrace) !void {
    try std.dwarf.openDwarfDebugInfo(dwarf_info, kernel_panic_allocator);

    var frame_index: usize = 0;
    var frames_left: usize = std.math.min(stack_trace.index, stack_trace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frame_index];

        var compile_unit = dwarf_info.findCompileUnit(return_address) catch {
            kprint.write("{: >3} ? ?:? ??? Line info not available ???\r", .{frames_left});
            continue;
        };

        if (dwarf_info.getLineNumberInfo(kernel_panic_allocator, compile_unit.*, return_address)) |line_info| {
            kprint.write("{: >3} {x:0>16} {s}:{}:{}\r", .{
                frames_left,
                return_address,
                line_info.file_name,
                line_info.line,
                line_info.column,
            });
        } else |_| {
            kprint.write("{: >3} {x:0>16} ?:? ??? Line info not available ???\r", .{ frames_left, return_address });
        }
    }
}

fn extractDwarfInfo(kernel: *kernel_elf.KernelElf) !std.dwarf.DwarfInfo {
    var section_headers_arr: [64]std.elf.Elf64_Shdr = undefined;
    var section_headers = section_headers_arr[0..kernel.header.shnum];

    // Build array of section headers
    var idx: u32 = 0;
    var section_headers_iter = kernel.header.section_header_iterator(&kernel.stream);

    while (try section_headers_iter.next()) |section| {
        section_headers[idx] = section;
        idx += 1;
    }

    const sh_string_table = section_headers[kernel.header.shstrndx];
    var str_table_slice = kernel.data[sh_string_table.sh_offset..(sh_string_table.sh_offset + sh_string_table.sh_size)];

    var debug_info: []const u8 = undefined;
    var debug_str: []const u8 = undefined;
    var debug_line: []const u8 = undefined;
    var debug_ranges: []const u8 = undefined;
    var debug_abbrev: []const u8 = undefined;

    for (section_headers) |section| {
        var sh_name_str = std.mem.span(@ptrCast([*:0]u8, &str_table_slice[section.sh_name]));

        if (std.mem.eql(u8, sh_name_str, ".debug_info")) {
            debug_info = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if (std.mem.eql(u8, sh_name_str, ".debug_str")) {
            debug_str = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if (std.mem.eql(u8, sh_name_str, ".debug_line")) {
            debug_line = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if (std.mem.eql(u8, sh_name_str, ".debug_ranges")) {
            debug_ranges = kernel.data[section.sh_offset..(section.sh_offset + section.sh_size)];
        }

        if (std.mem.eql(u8, sh_name_str, ".debug_abbrev")) {
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
        .debug_line_str = null,
        .debug_loclists = null,
        .debug_rnglists = null,
        .debug_addr = null,
        .debug_names = null,
        .debug_frame = null,
        .debug_str_offsets = null,
    };
}

var already_panicking: bool = false;

extern fn exit() noreturn;

pub fn handlePanic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    if (already_panicking) {
        kprint.write("Double panic\r", .{});
        while (true) {}
    }
    already_panicking = true;

    printGuru(msg);

    var debug_info = extractDwarfInfo(kernel_elf.get()) catch unreachable;

    if (error_return_trace) |stack_trace| {
        kprint.write("Dumping stack trace\r", .{});
        dumpStackTrace(&debug_info, stack_trace) catch unreachable;
    } else {
        kprint.write("No stack trace available\r", .{});
    }

    exit();
}

pub fn printGuru(msg: []const u8) void {
    kprint.write("+=================+\r", .{});
    kprint.write("| GURU MEDITATION |\r", .{});
    kprint.write("+=================+\r", .{});
    kprint.write("\r", .{});
    kprint.write("Message: {s}\r", .{msg});
    kprint.write("\r", .{});
}

pub fn printAddress(address:u64) !void {   
    var debug_info = try extractDwarfInfo(kernel_elf.get());
    try std.dwarf.openDwarfDebugInfo(&debug_info, kernel_panic_allocator);

    var compile_unit = debug_info.findCompileUnit(address) catch {
        kprint.write("0x{x:0>16} ??? ?:?  Line info not available ???\r", .{ address });
        return;
    };

    if (debug_info.getLineNumberInfo(kernel_panic_allocator, compile_unit.*, address)) |line_info| {
        kprint.write("0x{x:0>16} {s}:{}:{}\r", .{
            address,
            line_info.file_name,
            line_info.line,
            line_info.column,
        });
    } else |_| {
        kprint.write("0x{x:0>16} ?:? ??? Line info not available ???\r", .{ address });
    }
}