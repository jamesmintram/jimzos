const kernel = @import("kernel_test");

test {
    _ = kernel.phys_range;
    _ = kernel.boot_info;
    _ = kernel.bus;
    _ = kernel.interrupt;
    _ = kernel.mmio_region;
    _ = kernel.timer;
}

const std = @import("std");
const DeviceTree = kernel.DeviceTree;
const boot = kernel.boot_info;
const bus = kernel.bus;
const fdt_boot = kernel.fdt_boot;
const fdt_util = kernel.fdt;
const interrupt = kernel.interrupt;
const gic_v3_fdt = kernel.gic_v3_fdt;
const MmioRegion = kernel.mmio_region.MmioRegion;

const FakeMemorySpace = struct {
    fn map(_: *anyopaque, _: bus.AddressRange) anyerror!MmioRegion {
        return error.UnexpectedMmioMap;
    }
};

fn fakeParentBus(context: *u8) bus.Bus {
    return .{
        .memory = .{
            .context = context,
            .vtable = &.{ .map = FakeMemorySpace.map },
        },
    };
}

fn allocatorMetadataRequirement(_: []const boot.PhysRange) anyerror!boot.ReservationRequirement {
    return .{ .size = boot.page_size };
}

test "FDT boot discovery handles banks, reservations, no-map and CPUs" {
    const embedded = @embedFile("memory_test_dtb");
    var aligned: [embedded.len]u8 align(8) = undefined;
    @memcpy(&aligned, embedded);

    const fdt = try fdt_boot.discoverFromSlice(0x70000000, &aligned);
    const builder = try fdt_boot.parse(fdt);
    const info = try builder.finish(allocatorMetadataRequirement);

    try std.testing.expectEqualSlices(boot.PhysRange, &.{
        .{ .start = 0x40000000, .end = 0x41000000 },
        .{ .start = 0x50000000, .end = 0x50800000 },
    }, info.memory.constSlice());
    try std.testing.expectEqual(@as(usize, 2), info.cpus.len);
    try std.testing.expectEqual(boot.CpuDescriptor.EnableMethod.psci, info.cpus.items[1].enable_method);

    var found_memreserve = false;
    var found_no_map = false;
    for (info.reserved.constSlice()) |reservation| {
        if (reservation.kind == .fdt_reservation and reservation.range.start == 0x40002000) {
            found_memreserve = true;
        }
        if (reservation.kind == .reserved_memory and reservation.range.start == 0x40004000) {
            found_no_map = reservation.no_map;
        }
    }
    try std.testing.expect(found_memreserve);
    try std.testing.expect(found_no_map);
    try std.testing.expectEqualSlices(boot.PhysRange, &.{
        .{ .start = 0x40001000, .end = 0x40002000 },
        .{ .start = 0x40003000, .end = 0x40004000 },
        .{ .start = 0x40006000, .end = 0x41000000 },
        .{ .start = 0x50000000, .end = 0x50800000 },
    }, info.usable.constSlice());
}

test "shared FDT helpers validate properties and register cells" {
    const embedded = @embedFile("memory_test_dtb");
    var aligned: [embedded.len]u8 align(8) = undefined;
    @memcpy(&aligned, embedded);

    const fdt = try fdt_boot.discoverFromSlice(0x70000000, &aligned);
    const dt = fdt.tree;
    const root = DeviceTree.Node.root;

    try std.testing.expect(try fdt_util.hasProperty(dt, root, "model"));
    try std.testing.expect(!try fdt_util.hasProperty(dt, root, "missing"));
    try std.testing.expectEqualStrings(
        "JimZOS FDT helper fixture",
        (try fdt_util.stringProperty(dt, root, "model")).?,
    );
    try std.testing.expectEqual(
        @as(?[:0]const u8, null),
        try fdt_util.stringProperty(dt, root, "missing"),
    );
    try std.testing.expectError(
        error.InvalidStringProperty,
        fdt_util.stringProperty(dt, root, "test-invalid-string"),
    );
    try std.testing.expectError(
        error.InvalidStringListProperty,
        fdt_util.stringListProperty(dt, root, "test-invalid-string"),
    );

    var compatible = (try fdt_util.stringListProperty(dt, root, "compatible")).?;
    try std.testing.expectEqualStrings("jimzos,memory-test", (try compatible.next()).?);
    try std.testing.expectEqualStrings("simple-bus", (try compatible.next()).?);
    try std.testing.expectEqual(@as(?[:0]const u8, null), try compatible.next());

    try std.testing.expectEqual(
        @as(?u32, 0x12345678),
        try fdt_util.u32Property(dt, root, "test-u32"),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x123456789abcdef0),
        try fdt_util.u64Property(dt, root, "test-u64"),
    );
    try std.testing.expectEqual(
        @as(?u32, null),
        try fdt_util.u32Property(dt, root, "missing"),
    );
    try std.testing.expectError(
        error.InvalidU32Property,
        fdt_util.u32Property(dt, root, "test-invalid-scalar"),
    );
    try std.testing.expectError(
        error.InvalidU64Property,
        fdt_util.u64Property(dt, root, "test-invalid-scalar"),
    );

    try std.testing.expect(try root.checkCompatible(dt, "jimzos,memory-test"));
    try std.testing.expect(try root.checkCompatible(dt, "simple-bus"));
    try std.testing.expect(!try root.checkCompatible(dt, "not-compatible"));

    const status_ok = (try dt.nodeFromPath("/test-status-ok")).?.node;
    const status_okay = (try dt.nodeFromPath("/test-status-okay")).?.node;
    const memory = (try dt.nodeFromPath("/memory@40000000")).?.node;
    const disabled_memory = (try dt.nodeFromPath("/memory@60000000")).?.node;
    try std.testing.expect(try fdt_util.statusOkay(dt, status_ok));
    try std.testing.expect(try fdt_util.statusOkay(dt, status_okay));
    try std.testing.expect(try fdt_util.statusOkay(dt, memory));
    try std.testing.expect(!try fdt_util.statusOkay(dt, disabled_memory));

    const memory_cells = try fdt_util.parentRegisterCells(dt, memory);
    try std.testing.expectEqual(@as(u32, 2), memory_cells.address_cells);
    try std.testing.expectEqual(@as(u32, 2), memory_cells.size_cells);
    var memory_registers = try fdt_util.parentMmioRegisterIterator(dt, memory);
    try std.testing.expectEqual(
        DeviceTree.Property.Value.RegValue{
            .address = 0x40000000,
            .size = 0x01000000,
        },
        memory_registers.next().?,
    );

    const cpu = (try dt.nodeFromPath("/cpus/cpu@0")).?.node;
    const cpu_cells = try fdt_util.parentRegisterCells(dt, cpu);
    try std.testing.expectEqual(@as(u32, 2), cpu_cells.address_cells);
    try std.testing.expectEqual(@as(u32, 0), cpu_cells.size_cells);
    var cpu_registers = try fdt_util.parentRegisterIterator(dt, cpu);
    try std.testing.expectEqual(
        DeviceTree.Property.Value.RegValue{ .address = 0, .size = 0 },
        cpu_registers.next().?,
    );
    try std.testing.expectError(
        error.UnsupportedMmioRegisterCells,
        fdt_util.parentMmioRegisterIterator(dt, cpu),
    );

    const size_only = (try dt.nodeFromPath("/size-only-bus/size-only-resource@0")).?.node;
    const size_only_cells = try fdt_util.parentRegisterCells(dt, size_only);
    try std.testing.expectEqual(@as(u32, 0), size_only_cells.address_cells);
    try std.testing.expectEqual(@as(u32, 1), size_only_cells.size_cells);
    var size_only_registers = try fdt_util.parentRegisterIterator(dt, size_only);
    try std.testing.expectEqual(
        DeviceTree.Property.Value.RegValue{ .address = 0, .size = 0x2000 },
        size_only_registers.next().?,
    );

    try std.testing.expectError(
        error.UnsupportedRegisterCells,
        fdt_util.registerIterator(dt, memory, .{ .address_cells = 0, .size_cells = 0 }),
    );
    try std.testing.expectError(
        error.MissingRegisterParent,
        fdt_util.parentRegisterCells(dt, root),
    );
}

test "FDT attach arguments resolve MMIO and interrupt resources" {
    const embedded = @embedFile("memory_test_dtb");
    var aligned: [embedded.len]u8 align(8) = undefined;
    @memcpy(&aligned, embedded);

    const fdt = try fdt_boot.discoverFromSlice(0x70000000, &aligned);
    const dt = fdt.tree;
    const gic_node = (try dt.nodeFromPath("/interrupt-controller@8000000")).?.node;
    const timer_node = (try dt.nodeFromPath("/timer")).?.node;
    const extended_node = (try dt.nodeFromPath("/test-interrupts-extended")).?.node;
    var memory_context: u8 = 0;
    const parent_bus = fakeParentBus(&memory_context);

    const gic_args = fdt_util.FdtAttachArgs{
        .tree = dt,
        .node = gic_node,
        .parent_bus = parent_bus,
    };
    try std.testing.expectEqual(
        bus.AddressRange{ .start = 0x08000000, .byte_len = 0x00010000 },
        (try gic_args.mmio(0)).range,
    );
    try std.testing.expectEqual(
        bus.AddressRange{ .start = 0x080a0000, .byte_len = 0x00f60000 },
        (try gic_args.mmio(1)).range,
    );
    try std.testing.expectError(error.MmioIndexOutOfRange, gic_args.mmio(2));

    const FakeController = struct {
        fn establish(
            _: *anyopaque,
            _: interrupt.Route,
            _: *const fn (*anyopaque) void,
            _: *anyopaque,
        ) !void {}
    };
    var controller_context: u8 = 0;
    try fdt_util.registerInterruptController(.{
        .node = gic_node,
        .controller = .{
            .context = &controller_context,
            .establish_function = FakeController.establish,
        },
        .decode = gic_v3_fdt.decodeInterrupt,
    });

    const timer_args = fdt_util.FdtAttachArgs{
        .tree = dt,
        .node = timer_node,
        .parent_bus = parent_bus,
    };
    try std.testing.expectEqual(
        interrupt.Route{ .line = 30, .trigger = .level_high },
        (try timer_args.interrupt(1)).route,
    );
    try std.testing.expectEqual(
        interrupt.Route{ .line = 37, .trigger = .edge_rising },
        (try fdt_util.interruptResource(
            try fdt_util.interruptSpecifier(dt, extended_node, 0),
        )).route,
    );
    try std.testing.expectError(
        error.InterruptIndexOutOfRange,
        timer_args.interrupt(4),
    );
}
