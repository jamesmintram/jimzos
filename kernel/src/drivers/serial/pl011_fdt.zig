const std = @import("std");
const DeviceTree = @import("DeviceTree");
const bus = @import("../../bus.zig");
const Config = @import("pl011.zig").Config;
const fdt_util = @import("../../fdt.zig");

pub const Resources = struct {
    registers: bus.MemoryResource,
    clock_hz: u32,
    baud: u32,

    pub fn map(self: Resources) !Config {
        return .{
            .registers = try self.registers.map(),
            .clock_hz = self.clock_hz,
            .baud = self.baud,
        };
    }
};

pub fn discover(dt: DeviceTree, parent_bus: bus.Bus) !Resources {
    const chosen = (try dt.nodeFromPath("/chosen")) orelse return error.MissingChosen;
    const stdout_path = (try fdt_util.stringProperty(dt, chosen.node, "stdout-path")) orelse
        return error.MissingStdoutPath;

    const separator = std.mem.indexOfScalar(u8, stdout_path, ':');
    const node_path = if (separator) |index| stdout_path[0..index] else stdout_path;
    const node = (try dt.nodeFromPath(node_path)) orelse return error.ConsoleNotFound;
    if (!try node.node.checkCompatible(dt, "arm,pl011")) return error.UnsupportedConsole;

    var register_values = try fdt_util.parentMmioRegisterIterator(dt, node.node);
    const register = register_values.next() orelse return error.MissingRegisters;

    const clock_hz = try resolveClock(dt, node.node);
    return .{
        .registers = try parent_bus.mmio(register.address, register.size),
        .clock_hz = clock_hz,
        .baud = try parseBaud(stdout_path, separator),
    };
}

fn resolveClock(dt: DeviceTree, node: DeviceTree.Node) !u32 {
    if (try fdt_util.u32Property(dt, node, "clock-frequency")) |clock_hz| return clock_hz;

    const property = (try fdt_util.property(dt, node, "clocks")) orelse return error.MissingClock;
    var handles = try property.value.pHandleListIterator();
    const handle = handles.next() orelse return error.MissingClock;
    const clock_node = (try handle.node(dt)) orelse return error.MissingClock;
    return (try fdt_util.u32Property(dt, clock_node.node, "clock-frequency")) orelse error.MissingClock;
}

fn parseBaud(stdout_path: []const u8, separator: ?usize) !u32 {
    const start = (separator orelse return 115200) + 1;
    var end = start;
    while (end < stdout_path.len and std.ascii.isDigit(stdout_path[end])) : (end += 1) {}
    if (end == start) return 115200;
    return std.fmt.parseInt(u32, stdout_path[start..end], 10);
}
