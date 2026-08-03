const std = @import("std");
const mmu = @import("../arch/mmu.zig");
const DeviceTree = @import("DeviceTree");
const boot = @import("boot_info.zig");
const fdt_util = @import("../fdt.zig");

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
    const address_cells = (try fdt_util.u32Property(dt, .root, "#address-cells")) orelse
        return error.MissingRootAddressCells;
    const size_cells = (try fdt_util.u32Property(dt, .root, "#size-cells")) orelse
        return error.MissingRootSizeCells;
    try validateCells(address_cells, size_cells);

    var nodes = try dt.nodeIterator(.root, .direct_children, .{ .name = "memory" });
    while (try nodes.next(dt)) |memory| {
        if (!try fdt_util.statusOkay(dt, memory.node)) continue;
        if (!try fdt_util.stringPropertyEquals(dt, memory.node, "device_type", "memory")) {
            return error.InvalidMemoryNode;
        }
        const property = (try fdt_util.property(dt, memory.node, "reg")) orelse
            return error.MissingMemoryRegisters;
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
    const address_cells = (try fdt_util.u32Property(dt, parent.node, "#address-cells")) orelse
        return error.MissingReservedAddressCells;
    const size_cells = (try fdt_util.u32Property(dt, parent.node, "#size-cells")) orelse
        return error.MissingReservedSizeCells;
    try validateCells(address_cells, size_cells);

    var nodes = try dt.nodeIterator(parent.node, .direct_children, .any);
    while (try nodes.next(dt)) |node| {
        if (!try fdt_util.statusOkay(dt, node.node)) continue;
        const no_map = try fdt_util.hasProperty(dt, node.node, "no-map");
        if (try fdt_util.property(dt, node.node, "reg")) |property| {
            var registers = try property.value.regIterator(address_cells, size_cells);
            while (registers.next()) |register| {
                if (register.size == 0) continue;
                try builder.addReservation(
                    try boot.PhysRange.fromStartSize(register.address, register.size),
                    .reserved_memory,
                    no_map,
                    try fdt_util.hasProperty(dt, node.node, "reusable"),
                );
            }
        } else if (try fdt_util.hasProperty(dt, node.node, "size")) {
            return error.UnsupportedDynamicReservedMemory;
        } else {
            return error.InvalidReservedMemoryNode;
        }
    }
}

fn parseCpus(builder: *boot.Builder) !void {
    const dt = builder.fdt.tree;
    const parent = (try dt.nodeFromPath("/cpus")) orelse return error.MissingCpus;
    const address_cells = (try fdt_util.u32Property(dt, parent.node, "#address-cells")) orelse
        return error.MissingCpuAddressCells;
    const size_cells = (try fdt_util.u32Property(dt, parent.node, "#size-cells")) orelse
        return error.MissingCpuSizeCells;
    if (address_cells == 0 or address_cells > 2 or size_cells != 0) return error.UnsupportedCpuCells;

    var nodes = try dt.nodeIterator(parent.node, .direct_children, .{ .name = "cpu" });
    while (try nodes.next(dt)) |cpu| {
        if (!try fdt_util.stringPropertyEquals(dt, cpu.node, "device_type", "cpu")) {
            return error.InvalidCpuNode;
        }
        const property = (try fdt_util.property(dt, cpu.node, "reg")) orelse return error.MissingCpuId;
        var registers = try property.value.regIterator(address_cells, 0);
        const register = registers.next() orelse return error.MissingCpuId;
        try builder.cpus.append(.{
            .id = register.address,
            .enabled = try fdt_util.statusOkay(dt, cpu.node),
            .enable_method = try cpuEnableMethod(dt, cpu.node),
            .release_address = try fdt_util.u64Property(dt, cpu.node, "cpu-release-addr"),
        });
    }
    if (builder.cpus.len == 0) return error.NoCpus;
}

fn cpuEnableMethod(dt: DeviceTree, node: DeviceTree.Node) !boot.CpuDescriptor.EnableMethod {
    var methods = (try fdt_util.stringListProperty(dt, node, "enable-method")) orelse return .none;
    while (try methods.next()) |method| {
        if (std.mem.eql(u8, method, "psci")) return .psci;
        if (std.mem.eql(u8, method, "spin-table")) return .spin_table;
    }
    return .unknown;
}

fn validateCells(address_cells: u32, size_cells: u32) !void {
    if (address_cells == 0 or address_cells > 2 or size_cells == 0 or size_cells > 2) {
        return error.UnsupportedCellWidth;
    }
}

fn readBe32(bytes: *align(1) const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}
