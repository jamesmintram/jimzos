const std = @import("std");
const DeviceTree = @import("DeviceTree");
const kprint = @import("../kprint.zig");
const BootInfo = @import("boot_info.zig").BootInfo;
const Config = @import("../drivers/serial/pl011.zig").Config;

/// Print the full path of every node in the device tree, root first then all
/// descendants in tree order (nodeIterator walks root's children, so root `/`
/// is printed separately).
pub fn dumpFdtNodes(dt: DeviceTree) !void {
    var buf: [256]u8 = undefined;

    kprint.write("  {s}\r", .{try DeviceTree.Node.root.path(dt, &buf)});

    var iter = try dt.nodeIterator(.root, .all_children, .any);
    while (try iter.next(dt)) |node| {
        kprint.write("  {s}\r", .{try node.node.path(dt, &buf)});
    }
}

pub fn dumpMemoryNodes(dt: DeviceTree) !void {
    const address_cells = (try DeviceTree.Node.root.addressCells(dt)) orelse 2;
    const size_cells = (try DeviceTree.Node.root.sizeCells(dt)) orelse 1;

    var nodes = try dt.nodeIterator(.root, .all_children, .{ .name = "memory" });
    while (try nodes.next(dt)) |node| {
        kprint.write("  {s}:\r", .{node.name});

        var properties = try node.node.propertyIterator(dt, .any);
        while (try properties.next()) |property| {
            try printProperty(property, address_cells, size_cells);
        }
    }
}

fn printProperty(property: DeviceTree.Property, address_cells: u32, size_cells: u32) !void {
    if (std.mem.eql(u8, property.name, "reg")) {
        kprint.write("    {s} =", .{property.name});
        var registers = try property.value.regIterator(address_cells, size_cells);
        while (registers.next()) |register| {
            kprint.write(" <0x{x} 0x{x}>", .{ register.address, register.size });
        }
        kprint.write("\r", .{});
    } else if (looksLikeString(property.value._raw)) {
        kprint.write("    {s} = \"{s}\"\r", .{ property.name, property.value.toString() });
    } else {
        kprint.write("    {s} = <", .{property.name});
        for (property.value._raw) |byte| kprint.write("{x:0>2}", .{byte});
        kprint.write(">\r", .{});
    }
}

fn looksLikeString(raw: []const u8) bool {
    if (raw.len == 0 or raw[raw.len - 1] != 0) return false;
    for (raw[0 .. raw.len - 1]) |byte| {
        if (byte != 0 and (byte < 0x20 or byte > 0x7e)) return false;
    }
    return true;
}

pub fn dumpConsole(config: Config) void {
    kprint.write("  PL011 base = 0x{x}, size = 0x{x}\r", .{
        config.registers.physicalBase(),
        config.registers.size(),
    });
    kprint.write("  clock = {} Hz, baud = {}\r", .{ config.clock_hz, config.baud });
}

pub fn dumpBootInfo(info: *const BootInfo) void {
    kprint.write("boot memory: {} MiB reported, {} MiB usable\r", .{
        info.totalMemoryBytes() / (1024 * 1024),
        info.totalUsableBytes() / (1024 * 1024),
    });
    for (info.memory.constSlice()) |range| {
        kprint.write("  RAM  [0x{x}, 0x{x})\r", .{ range.start, range.end });
    }
    for (info.reserved.constSlice()) |reservation| {
        kprint.write("  RSV  [0x{x}, 0x{x}) {s}{s}\r", .{
            reservation.range.start,
            reservation.range.end,
            @tagName(reservation.kind),
            if (reservation.no_map) " no-map" else "",
        });
    }
    for (info.usable.constSlice()) |range| {
        kprint.write("  FREE [0x{x}, 0x{x})\r", .{ range.start, range.end });
    }
    kprint.write("boot CPUs: {}, boot id 0x{x}\r", .{ info.cpus.len, info.boot_cpu_id });
}
