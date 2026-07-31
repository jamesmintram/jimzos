const std = @import("std");
const mmu = @import("../arch/mmu.zig");
const DeviceTree = @import("DeviceTree");
const boot = @import("boot_info.zig");

const max_fdt_size: u32 = 2 * 1024 * 1024;

pub fn discover(fdt_phys: u64) !boot.FdtBlob {
    return openBlob(fdt_phys);
}

pub fn discoverFromSlice(fdt_phys: u64, bytes: []align(8) const u8) !boot.FdtBlob {
    if (bytes.len > max_fdt_size) return error.InvalidFdtSize;
    return .{
        .physical_address = fdt_phys,
        .size = @intCast(bytes.len),
        .tree = try DeviceTree.fromSlice(bytes),
    };
}

pub fn parse(fdt: boot.FdtBlob) !boot.Builder {
    var builder = boot.Builder.init(fdt, fdt.tree.bootCpuid() orelse 0);
    try parseMemory(&builder);
    try parseReservationBlock(&builder);
    try parseReservedMemory(&builder);
    try parseCpus(&builder);
    return builder;
}

fn openBlob(fdt_phys: u64) !boot.FdtBlob {
    if (fdt_phys & 7 != 0) return error.FdtNotAligned;
    const virtual = mmu.physicalToVirtual(fdt_phys) catch return error.FdtAddressOverflow;
    const ptr: [*]align(8) const u8 = @ptrFromInt(virtual);
    const magic = readBe32(ptr[0..4]);
    if (magic != 0xd00dfeed) return error.BadFdtMagic;
    const size = readBe32(ptr[4..8]);
    if (size < 40 or size > max_fdt_size) return error.InvalidFdtSize;
    const bytes: []align(8) const u8 = ptr[0..size];
    return .{
        .physical_address = fdt_phys,
        .size = size,
        .tree = try DeviceTree.fromSlice(bytes),
    };
}

fn parseMemory(builder: *boot.Builder) !void {
    const dt = builder.fdt.tree;
    const address_cells = (try DeviceTree.Node.root.addressCells(dt)) orelse return error.MissingRootAddressCells;
    const size_cells = (try DeviceTree.Node.root.sizeCells(dt)) orelse return error.MissingRootSizeCells;
    try validateCells(address_cells, size_cells);

    var nodes = try dt.nodeIterator(.root, .direct_children, .{ .name = "memory" });
    while (try nodes.next(dt)) |memory| {
        if (!try statusOkay(dt, memory.node)) continue;
        if (!try propertyEquals(dt, memory.node, "device_type", "memory")) return error.InvalidMemoryNode;
        var properties = try memory.node.propertyIterator(dt, .{ .name = "reg" });
        const property = (try properties.next()) orelse return error.MissingMemoryRegisters;
        var registers = try property.value.regIterator(address_cells, size_cells);
        var found = false;
        while (registers.next()) |register| {
            found = true;
            if (register.size == 0) continue;
            try builder.addMemory(try boot.PhysRange.fromStartSize(register.address, register.size));
        }
        if (!found) return error.MissingMemoryRegisters;
    }
    if (builder.memory.len == 0) return error.NoUsableMemoryNodes;
}

fn parseReservationBlock(builder: *boot.Builder) !void {
    var reservations = builder.fdt.tree.memoryReservationIterator();
    while (try reservations.next()) |reservation| {
        if (reservation.size == 0) continue;
        try builder.addReservation(
            try boot.PhysRange.fromStartSize(reservation.address, reservation.size),
            .fdt_reservation,
            false,
            false,
        );
    }
}

fn parseReservedMemory(builder: *boot.Builder) !void {
    const dt = builder.fdt.tree;
    const parent = (try dt.nodeFromPath("/reserved-memory")) orelse return;
    const address_cells = (try parent.node.addressCells(dt)) orelse return error.MissingReservedAddressCells;
    const size_cells = (try parent.node.sizeCells(dt)) orelse return error.MissingReservedSizeCells;
    try validateCells(address_cells, size_cells);

    var nodes = try dt.nodeIterator(parent.node, .direct_children, .any);
    while (try nodes.next(dt)) |node| {
        if (!try statusOkay(dt, node.node)) continue;
        const no_map = try hasProperty(dt, node.node, "no-map");
        var properties = try node.node.propertyIterator(dt, .{ .name = "reg" });
        if (try properties.next()) |property| {
            var registers = try property.value.regIterator(address_cells, size_cells);
            while (registers.next()) |register| {
                if (register.size == 0) continue;
                try builder.addReservation(
                    try boot.PhysRange.fromStartSize(register.address, register.size),
                    .reserved_memory,
                    no_map,
                    try hasProperty(dt, node.node, "reusable"),
                );
            }
        } else if (try hasProperty(dt, node.node, "size")) {
            return error.UnsupportedDynamicReservedMemory;
        } else {
            return error.InvalidReservedMemoryNode;
        }
    }
}

fn parseCpus(builder: *boot.Builder) !void {
    const dt = builder.fdt.tree;
    const parent = (try dt.nodeFromPath("/cpus")) orelse return error.MissingCpus;
    const address_cells = (try parent.node.addressCells(dt)) orelse return error.MissingCpuAddressCells;
    const size_cells = (try parent.node.sizeCells(dt)) orelse return error.MissingCpuSizeCells;
    if (address_cells == 0 or address_cells > 2 or size_cells != 0) return error.UnsupportedCpuCells;

    var nodes = try dt.nodeIterator(parent.node, .direct_children, .{ .name = "cpu" });
    while (try nodes.next(dt)) |cpu| {
        if (!try propertyEquals(dt, cpu.node, "device_type", "cpu")) return error.InvalidCpuNode;
        var properties = try cpu.node.propertyIterator(dt, .{ .name = "reg" });
        const property = (try properties.next()) orelse return error.MissingCpuId;
        var registers = try property.value.regIterator(address_cells, 0);
        const register = registers.next() orelse return error.MissingCpuId;
        try builder.cpus.append(.{
            .id = register.address,
            .enabled = try statusOkay(dt, cpu.node),
            .enable_method = try cpuEnableMethod(dt, cpu.node),
            .release_address = try optionalIntegerProperty(dt, cpu.node, "cpu-release-addr"),
        });
    }
    if (builder.cpus.len == 0) return error.NoCpus;
}

fn cpuEnableMethod(dt: DeviceTree, node: DeviceTree.Node) !boot.CpuDescriptor.EnableMethod {
    const value = (try propertyString(dt, node, "enable-method")) orelse return .none;
    if (std.mem.eql(u8, value, "psci")) return .psci;
    if (std.mem.eql(u8, value, "spin-table")) return .spin_table;
    return .unknown;
}

fn optionalIntegerProperty(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !?u64 {
    var properties = try node.propertyIterator(dt, .{ .name = name });
    const property = (try properties.next()) orelse return null;
    return switch (property.value._raw.len) {
        4 => property.value.toU32(),
        8 => property.value.toU64(),
        else => error.InvalidIntegerProperty,
    };
}

fn validateCells(address_cells: u32, size_cells: u32) !void {
    if (address_cells == 0 or address_cells > 2 or size_cells == 0 or size_cells > 2) {
        return error.UnsupportedCellWidth;
    }
}

fn statusOkay(dt: DeviceTree, node: DeviceTree.Node) !bool {
    const status = (try propertyString(dt, node, "status")) orelse return true;
    return std.mem.eql(u8, status, "ok") or std.mem.eql(u8, status, "okay");
}

fn propertyEquals(dt: DeviceTree, node: DeviceTree.Node, name: []const u8, expected: []const u8) !bool {
    const value = (try propertyString(dt, node, name)) orelse return false;
    return std.mem.eql(u8, value, expected);
}

fn propertyString(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !?[]const u8 {
    var properties = try node.propertyIterator(dt, .{ .name = name });
    return if (try properties.next()) |property| property.value.toString() else null;
}

fn hasProperty(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !bool {
    var properties = try node.propertyIterator(dt, .{ .name = name });
    return try properties.next() != null;
}

fn readBe32(bytes: *align(1) const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}
