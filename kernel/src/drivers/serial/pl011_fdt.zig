const std = @import("std");
const DeviceTree = @import("DeviceTree");
const Config = @import("pl011.zig").Config;
const MmioRegion = @import("../../io/mmio_region.zig").MmioRegion;

pub fn discover(dt: DeviceTree) !Config {
    const chosen = (try dt.nodeFromPath("/chosen")) orelse return error.MissingChosen;
    const stdout_path = blk: {
        var properties = try chosen.node.propertyIterator(dt, .{ .name = "stdout-path" });
        const property = (try properties.next()) orelse return error.MissingStdoutPath;
        break :blk property.value.toString();
    };

    const separator = std.mem.indexOfScalar(u8, stdout_path, ':');
    const node_path = if (separator) |index| stdout_path[0..index] else stdout_path;
    const node = (try dt.nodeFromPath(node_path)) orelse return error.ConsoleNotFound;
    if (!try isPl011(dt, node.node)) return error.UnsupportedConsole;

    const parent = (try node.node.parent(dt)) orelse return error.MissingConsoleParent;
    const address_cells = (try parent.node.addressCells(dt)) orelse 2;
    const size_cells = (try parent.node.sizeCells(dt)) orelse 1;

    var registers = try node.node.propertyIterator(dt, .{ .name = "reg" });
    const register_property = (try registers.next()) orelse return error.MissingRegisters;
    var register_values = try register_property.value.regIterator(address_cells, size_cells);
    const register = register_values.next() orelse return error.MissingRegisters;

    const clock_hz = try resolveClock(dt, node.node);
    return .{
        .registers = try MmioRegion.identityMapped(
            @intCast(register.address),
            @intCast(register.size),
        ),
        .clock_hz = clock_hz,
        .baud = try parseBaud(stdout_path, separator),
    };
}

fn isPl011(dt: DeviceTree, node: DeviceTree.Node) !bool {
    var properties = try node.propertyIterator(dt, .{ .name = "compatible" });
    const property = (try properties.next()) orelse return false;
    var strings = std.mem.splitScalar(u8, property.value._raw, 0);
    while (strings.next()) |value| {
        if (std.mem.eql(u8, value, "arm,pl011")) return true;
    }
    return false;
}

fn propertyU32(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !?u32 {
    var properties = try node.propertyIterator(dt, .{ .name = name });
    return if (try properties.next()) |property| property.value.toU32() else null;
}

fn resolveClock(dt: DeviceTree, node: DeviceTree.Node) !u32 {
    if (try propertyU32(dt, node, "clock-frequency")) |clock_hz| return clock_hz;

    var properties = try node.propertyIterator(dt, .{ .name = "clocks" });
    const property = (try properties.next()) orelse return error.MissingClock;
    var handles = try property.value.pHandleListIterator();
    const handle = handles.next() orelse return error.MissingClock;
    const clock_node = (try handle.node(dt)) orelse return error.MissingClock;
    return (try propertyU32(dt, clock_node.node, "clock-frequency")) orelse error.MissingClock;
}

fn parseBaud(stdout_path: []const u8, separator: ?usize) !u32 {
    const start = (separator orelse return 115200) + 1;
    var end = start;
    while (end < stdout_path.len and std.ascii.isDigit(stdout_path[end])) : (end += 1) {}
    if (end == start) return 115200;
    return std.fmt.parseInt(u32, stdout_path[start..end], 10);
}
