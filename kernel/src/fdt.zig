//! Shared helpers for querying flattened device trees.
//!
//! The DeviceTree dependency provides iteration and value decoding primitives.
//! This module adds the conventions JimZOS uses across boot code and drivers:
//! optional properties, validated scalar/string decoding, `status` handling,
//! and parent-cell-aware `reg` iteration.

const std = @import("std");
const DeviceTree = @import("DeviceTree");
const bus = @import("bus.zig");
const intr = @import("interrupt.zig");

const maximum_interrupt_controllers = 8;

pub const RegisterCells = struct {
    address_cells: u32,
    size_cells: u32,
};

/// A provider-specific interrupt specifier resolved from `interrupts` or
/// `interrupts-extended`. `cells` aliases the FDT and remains big-endian; the
/// interrupt provider owns their interpretation.
pub const InterruptSpecifier = struct {
    provider: DeviceTree.PHandle,
    provider_node: DeviceTree.Node,
    cells: []const u8,

    pub fn cellCount(self: InterruptSpecifier) usize {
        return self.cells.len / @sizeOf(u32);
    }

    pub fn cell(self: InterruptSpecifier, index: usize) !u32 {
        const offset = std.math.mul(usize, index, @sizeOf(u32)) catch
            return error.InterruptCellIndexOutOfRange;
        if (offset >= self.cells.len) return error.InterruptCellIndexOutOfRange;
        return readBigEndianCell(self.cells[offset..]);
    }
};

/// Resources presented to an FDT device by the bus which selected it.
///
/// `node` has already been matched and enabled by the attaching bus. MMIO
/// addresses remain in the immediate parent's address space: `parent_bus`
/// owns any required `ranges` translation before the resource is mapped.
pub const FdtAttachArgs = struct {
    tree: DeviceTree,
    node: DeviceTree.Node,
    parent_bus: bus.Bus,

    pub fn mmio(self: FdtAttachArgs, index: usize) !bus.MemoryResource {
        var registers = try parentMmioRegisterIterator(self.tree, self.node);
        var current_index: usize = 0;
        while (registers.next()) |register| : (current_index += 1) {
            if (current_index == index) {
                return self.parent_bus.mmio(register.address, register.size);
            }
        }
        return error.MmioIndexOutOfRange;
    }

    pub fn interrupt(self: FdtAttachArgs, index: usize) !intr.Resource {
        return interruptResource(try interruptSpecifier(self.tree, self.node, index));
    }
};

/// An attached FDT interrupt provider. The provider owns the interpretation of
/// its raw interrupt cells; this registry only follows the provider node.
pub const InterruptController = struct {
    node: DeviceTree.Node,
    controller: intr.Controller,
    decode: *const fn (InterruptSpecifier) anyerror!intr.Route,
};

var interrupt_controllers: [maximum_interrupt_controllers]InterruptController = undefined;
var interrupt_controller_count: usize = 0;

/// Publish an attached interrupt controller under its FDT node.
pub fn registerInterruptController(controller: InterruptController) !void {
    for (interrupt_controllers[0..interrupt_controller_count]) |registered| {
        if (registered.node == controller.node) {
            return error.InterruptControllerAlreadyRegistered;
        }
    }
    if (interrupt_controller_count == interrupt_controllers.len) {
        return error.InterruptControllerRegistryFull;
    }

    interrupt_controllers[interrupt_controller_count] = controller;
    interrupt_controller_count += 1;
}

/// Resolve raw FDT cells through the controller published for their provider
/// node. Consumers retain only the resulting controller-specific resource.
pub fn interruptResource(specifier: InterruptSpecifier) !intr.Resource {
    for (interrupt_controllers[0..interrupt_controller_count]) |registered| {
        if (registered.node != specifier.provider_node) continue;
        return .{
            .controller = registered.controller,
            .route = try registered.decode(specifier),
        };
    }
    return error.InterruptControllerNotAttached;
}

pub fn property(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
) !?DeviceTree.Property {
    var properties = try node.propertyIterator(dt, .{ .name = name });
    return try properties.next();
}

pub fn hasProperty(dt: DeviceTree, node: DeviceTree.Node, name: []const u8) !bool {
    return try property(dt, node, name) != null;
}

pub fn stringListProperty(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
) !?DeviceTree.Property.Value.StringListIterator {
    const found = (try property(dt, node, name)) orelse return null;
    const raw = found.value._raw;
    if (raw.len == 0 or raw[raw.len - 1] != 0) {
        return error.InvalidStringListProperty;
    }
    return found.value.stringListIterator();
}

pub fn stringProperty(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
) !?[:0]const u8 {
    const found = (try property(dt, node, name)) orelse return null;
    const raw = found.value._raw;
    if (raw.len == 0 or raw[raw.len - 1] != 0 or
        std.mem.indexOfScalar(u8, raw[0 .. raw.len - 1], 0) != null)
    {
        return error.InvalidStringProperty;
    }
    return found.value.toString();
}

pub fn u32Property(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
) !?u32 {
    const found = (try property(dt, node, name)) orelse return null;
    if (found.value._raw.len != @sizeOf(u32)) return error.InvalidU32Property;
    return found.value.toU32();
}

pub fn u64Property(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
) !?u64 {
    const found = (try property(dt, node, name)) orelse return null;
    if (found.value._raw.len != @sizeOf(u64)) return error.InvalidU64Property;
    return found.value.toU64();
}

pub fn stringPropertyEquals(
    dt: DeviceTree,
    node: DeviceTree.Node,
    name: []const u8,
    expected: []const u8,
) !bool {
    const value = (try stringProperty(dt, node, name)) orelse return false;
    return std.mem.eql(u8, value, expected);
}

/// A missing status means enabled. Both the specification's `okay` spelling
/// and the commonly emitted `ok` shorthand are accepted.
pub fn statusOkay(dt: DeviceTree, node: DeviceTree.Node) !bool {
    const status = (try stringProperty(dt, node, "status")) orelse return true;
    return std.mem.eql(u8, status, "ok") or std.mem.eql(u8, status, "okay");
}

/// Return the cell widths used to decode a node's `reg` property. Per the DT
/// specification, missing parent declarations default to 2 address cells and
/// 1 size cell.
pub fn parentRegisterCells(dt: DeviceTree, node: DeviceTree.Node) !RegisterCells {
    const parent = (try node.parent(dt)) orelse return error.MissingRegisterParent;
    const cells = RegisterCells{
        .address_cells = (try u32Property(dt, parent.node, "#address-cells")) orelse 2,
        .size_cells = (try u32Property(dt, parent.node, "#size-cells")) orelse 1,
    };
    try validateRegisterCells(cells);
    return cells;
}

pub fn registerIterator(
    dt: DeviceTree,
    node: DeviceTree.Node,
    cells: RegisterCells,
) !DeviceTree.Property.Value.RegIterator {
    try validateRegisterCells(cells);
    const registers = (try property(dt, node, "reg")) orelse return error.MissingRegisters;
    return try registers.value.regIterator(cells.address_cells, cells.size_cells);
}

/// Decode `reg` using the immediate parent's cell widths. Returned addresses
/// remain in that parent's bus address space; this does not translate `ranges`.
pub fn parentRegisterIterator(
    dt: DeviceTree,
    node: DeviceTree.Node,
) !DeviceTree.Property.Value.RegIterator {
    return registerIterator(dt, node, try parentRegisterCells(dt, node));
}

/// Decode address-bearing, sized MMIO entries using the immediate parent's
/// cell widths. Addresses remain in the parent bus space; callers must only
/// treat them as CPU-physical when the bus mapping is known to be identity.
pub fn parentMmioRegisterIterator(
    dt: DeviceTree,
    node: DeviceTree.Node,
) !DeviceTree.Property.Value.RegIterator {
    const cells = try parentRegisterCells(dt, node);
    if (cells.address_cells == 0 or cells.size_cells == 0) {
        return error.UnsupportedMmioRegisterCells;
    }
    return registerIterator(dt, node, cells);
}

/// Resolve one interrupt entry without interpreting its provider-specific
/// cells. `interrupts-extended` takes precedence when present; otherwise the
/// inherited `interrupt-parent` is used with the node's `interrupts` list.
pub fn interruptSpecifier(
    dt: DeviceTree,
    node: DeviceTree.Node,
    index: usize,
) !InterruptSpecifier {
    if (try property(dt, node, "interrupts-extended")) |extended| {
        return extendedInterruptSpecifier(dt, extended.value._raw, index);
    }

    const interrupts = (try property(dt, node, "interrupts")) orelse
        return error.MissingInterrupts;
    const provider = try inheritedInterruptParent(dt, node);
    const provider_node = (try provider.node(dt)) orelse
        return error.InterruptProviderNotFound;
    const cell_count = try interruptCellCount(dt, provider_node.node);
    const specifier_size = try interruptSpecifierSize(cell_count);
    if (interrupts.value._raw.len % specifier_size != 0) {
        return error.InvalidInterruptsProperty;
    }

    const offset = std.math.mul(usize, index, specifier_size) catch
        return error.InterruptIndexOutOfRange;
    const end = std.math.add(usize, offset, specifier_size) catch
        return error.InterruptIndexOutOfRange;
    if (end > interrupts.value._raw.len) return error.InterruptIndexOutOfRange;

    return .{
        .provider = provider,
        .provider_node = provider_node.node,
        .cells = interrupts.value._raw[offset..end],
    };
}

fn extendedInterruptSpecifier(
    dt: DeviceTree,
    raw: []const u8,
    requested_index: usize,
) !InterruptSpecifier {
    var remaining = raw;
    var index: usize = 0;

    while (remaining.len != 0) : (index += 1) {
        const provider_value = try readBigEndianCell(remaining);
        const provider: DeviceTree.PHandle = @enumFromInt(provider_value);
        remaining = remaining[@sizeOf(u32)..];

        const provider_node = (try provider.node(dt)) orelse
            return error.InterruptProviderNotFound;
        const cell_count = try interruptCellCount(dt, provider_node.node);
        const specifier_size = try interruptSpecifierSize(cell_count);
        if (remaining.len < specifier_size) return error.InvalidInterruptsExtendedProperty;

        if (index == requested_index) {
            return .{
                .provider = provider,
                .provider_node = provider_node.node,
                .cells = remaining[0..specifier_size],
            };
        }
        remaining = remaining[specifier_size..];
    }

    return error.InterruptIndexOutOfRange;
}

fn inheritedInterruptParent(
    dt: DeviceTree,
    starting_node: DeviceTree.Node,
) !DeviceTree.PHandle {
    var node = starting_node;
    while (true) {
        if (try u32Property(dt, node, "interrupt-parent")) |value| {
            return @enumFromInt(value);
        }
        node = if (try node.parent(dt)) |parent|
            parent.node
        else
            return error.MissingInterruptParent;
    }
}

fn interruptCellCount(dt: DeviceTree, provider: DeviceTree.Node) !u32 {
    const count = (try u32Property(dt, provider, "#interrupt-cells")) orelse
        return error.MissingInterruptCells;
    if (count == 0) return error.InvalidInterruptCells;
    return count;
}

fn interruptSpecifierSize(cell_count: u32) !usize {
    const count = std.math.cast(usize, cell_count) orelse
        return error.InvalidInterruptCells;
    return std.math.mul(usize, count, @sizeOf(u32)) catch
        return error.InvalidInterruptCells;
}

fn readBigEndianCell(raw: []const u8) !u32 {
    if (raw.len < @sizeOf(u32)) return error.TruncatedInterruptCell;
    return std.mem.readInt(u32, raw[0..@sizeOf(u32)], .big);
}

fn validateRegisterCells(cells: RegisterCells) !void {
    if (cells.address_cells > 2 or cells.size_cells > 2 or
        cells.address_cells + cells.size_cells == 0)
    {
        return error.UnsupportedRegisterCells;
    }
}
