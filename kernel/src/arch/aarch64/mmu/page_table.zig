//! Pure AArch64 stage-1 translation-table geometry and descriptor operations.
//!
//! This module has no knowledge of how table memory is addressed. MMU-off boot
//! code, the bootstrap direct map, and final-map construction access tables
//! through different address spaces but share these definitions.

const vm_page = @import("vm_page");

pub const Entry = u64;

pub const page_shift: u6 = vm_page.shift;
pub const page_size: usize = @intCast(vm_page.size);
pub const table_size: usize = page_size;
pub const entries_per_table: usize = 512;
pub const index_mask: usize = entries_per_table - 1;

pub const level_count: usize = 4;
pub const level_0_shift: u6 = 39;
pub const level_1_shift: u6 = 30;
pub const level_2_shift: u6 = 21;
pub const level_3_shift: u6 = page_shift;
pub const virtual_address_bits: u7 = 48;
pub const tcr_size_offset: u6 = 64 - virtual_address_bits;

pub const block_1g_size: u64 = 1024 * 1024 * 1024;
pub const block_2m_size: u64 = 2 * 1024 * 1024;

pub const table_address_mask: Entry = 0x0000_ffff_ffff_f000;
pub const physical_address_limit: u64 = table_address_mask + page_size;

pub const descriptor_valid: Entry = 0b01;
pub const descriptor_table_or_page: Entry = 0b11;
pub const descriptor_type_mask: Entry = 0b11;

pub const access_flag: Entry = 1 << 10;
pub const outer_shareable: Entry = 2 << 8;
pub const inner_shareable: Entry = 3 << 8;
pub const read_only: Entry = 1 << 7;
pub const attr_index_normal: Entry = 0 << 2;
pub const attr_index_device: Entry = 1 << 2;
pub const privileged_execute_never: Entry = 1 << 53;
pub const unprivileged_execute_never: Entry = 1 << 54;

pub const normal_attributes: Entry = access_flag | inner_shareable | attr_index_normal;
pub const device_attributes: Entry = access_flag | outer_shareable | attr_index_device;
pub const kernel_device_attributes: Entry = device_attributes |
    privileged_execute_never |
    unprivileged_execute_never;

pub const MemoryType = enum {
    normal,
    device,
};

pub const MapOptions = struct {
    /// Kernel mappings remain readable, EL1-only, and global. These fields
    /// select the memory type and the permissions that currently vary.
    memory_type: MemoryType,
    writable: bool,
    executable: bool,
};

pub fn kernelMappingAttributes(options: MapOptions) !Entry {
    if (options.memory_type == .device and options.executable) {
        return error.ExecutableDeviceMapping;
    }

    var attributes = switch (options.memory_type) {
        .normal => normal_attributes,
        .device => device_attributes,
    };
    if (!options.writable) attributes |= read_only;
    if (!options.executable) {
        attributes |= privileged_execute_never | unprivileged_execute_never;
    }
    return attributes;
}

pub inline fn indexFor(address: u64, shift: u6) usize {
    return @intCast((address >> shift) & index_mask);
}

pub inline fn isTableDescriptor(entry: Entry) bool {
    return entry & descriptor_type_mask == descriptor_table_or_page;
}

pub inline fn tableAddress(entry: Entry) u64 {
    return entry & table_address_mask;
}

pub inline fn tableDescriptor(physical_address: u64) Entry {
    return physical_address | descriptor_table_or_page;
}

pub inline fn blockDescriptor(physical_address: u64, attributes: Entry) Entry {
    return physical_address | attributes | descriptor_valid;
}

pub inline fn pageDescriptor(physical_address: u64, attributes: Entry) Entry {
    return physical_address | attributes | descriptor_table_or_page;
}

/// Install an absent descriptor, accepting an identical existing mapping.
/// A different address, descriptor type, or attribute remains a conflict.
pub fn ensureDescriptor(slot: *Entry, desired: Entry) !void {
    if (slot.* == desired) return;
    if (slot.* != 0) return error.MappingConflict;
    slot.* = desired;
}

comptime {
    if (page_size != 4096) {
        @compileError("the configured AArch64 translation granule must match the VM base page");
    }
    if (table_size != entries_per_table * @sizeOf(Entry)) {
        @compileError("AArch64 translation-table geometry is inconsistent");
    }
}

test "translation-table indices cover a 48-bit virtual address" {
    const std = @import("std");
    const address: u64 = 0xffff_1234_5678_9abc;
    try std.testing.expectEqual(@as(usize, 0x24), indexFor(address, level_0_shift));
    try std.testing.expectEqual(@as(usize, 0xd1), indexFor(address, level_1_shift));
    try std.testing.expectEqual(@as(usize, 0xb3), indexFor(address, level_2_shift));
    try std.testing.expectEqual(@as(usize, 0x189), indexFor(address, level_3_shift));
}

test "descriptor helpers preserve the table address" {
    const std = @import("std");
    const physical: u64 = 0x1234_5000;
    const descriptor = tableDescriptor(physical);
    try std.testing.expect(isTableDescriptor(descriptor));
    try std.testing.expectEqual(physical, tableAddress(descriptor));
    try std.testing.expectEqual(
        physical | normal_attributes | descriptor_table_or_page,
        pageDescriptor(physical, normal_attributes),
    );
}

test "descriptor installation is idempotent but rejects conflicts" {
    const std = @import("std");
    const desired = pageDescriptor(0x1234_5000, kernel_device_attributes);
    var slot: Entry = 0;

    try ensureDescriptor(&slot, desired);
    try std.testing.expectEqual(desired, slot);

    try ensureDescriptor(&slot, desired);
    try std.testing.expectEqual(desired, slot);

    try std.testing.expectError(
        error.MappingConflict,
        ensureDescriptor(&slot, pageDescriptor(0x1234_6000, kernel_device_attributes)),
    );
    try std.testing.expectError(
        error.MappingConflict,
        ensureDescriptor(&slot, pageDescriptor(0x1234_5000, normal_attributes)),
    );
    try std.testing.expectEqual(desired, slot);

    var page_slot = pageDescriptor(0x4000_0000, kernel_device_attributes);
    try std.testing.expectError(
        error.MappingConflict,
        ensureDescriptor(
            &page_slot,
            blockDescriptor(0x4000_0000, kernel_device_attributes),
        ),
    );
}

test "kernel mapping options encode memory type and permissions" {
    const std = @import("std");

    try std.testing.expectEqual(
        kernel_device_attributes,
        try kernelMappingAttributes(.{
            .memory_type = .device,
            .writable = true,
            .executable = false,
        }),
    );
    try std.testing.expectEqual(
        normal_attributes | read_only |
            privileged_execute_never |
            unprivileged_execute_never,
        try kernelMappingAttributes(.{
            .memory_type = .normal,
            .writable = false,
            .executable = false,
        }),
    );
    try std.testing.expectError(
        error.ExecutableDeviceMapping,
        kernelMappingAttributes(.{
            .memory_type = .device,
            .writable = false,
            .executable = true,
        }),
    );
}

test {
    _ = @import("layout.zig");
}
