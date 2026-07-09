test {
    _ = @import("vm/phys_range.zig");
    _ = @import("boot/boot_info.zig");
    _ = @import("io/mmio_region.zig");
}

const std = @import("std");
const boot = @import("boot/boot_info.zig");
const fdt_boot = @import("boot/fdt_boot.zig");

test "FDT boot discovery handles banks, reservations, no-map and CPUs" {
    const embedded = @embedFile("memory_test_dtb");
    var aligned: [embedded.len]u8 align(8) = undefined;
    @memcpy(&aligned, embedded);

    var builder = try fdt_boot.discoverFromSlice(0x70000000, &aligned);
    try builder.normalize();

    try std.testing.expectEqualSlices(boot.PhysRange, &.{
        .{ .start = 0x40000000, .end = 0x41000000 },
        .{ .start = 0x50000000, .end = 0x50800000 },
    }, builder.memory.constSlice());
    try std.testing.expectEqual(@as(usize, 2), builder.cpus.len);
    try std.testing.expectEqual(boot.CpuDescriptor.EnableMethod.psci, builder.cpus.items[1].enable_method);

    var found_memreserve = false;
    var found_no_map = false;
    for (builder.reserved.constSlice()) |reservation| {
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
        .{ .start = 0x40000000, .end = 0x40002000 },
        .{ .start = 0x40003000, .end = 0x40004000 },
        .{ .start = 0x40006000, .end = 0x41000000 },
        .{ .start = 0x50000000, .end = 0x50800000 },
    }, builder.usable.constSlice());
}
