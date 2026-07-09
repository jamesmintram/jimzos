const std = @import("std");
const DeviceTree = @import("DeviceTree");
const ranges = @import("../vm/phys_range.zig");

pub const PhysRange = ranges.PhysRange;
pub const page_size = ranges.page_size;

pub const max_memory_ranges = 32;
pub const max_reservations = 128;
pub const max_usable_ranges = 256;
pub const max_modules = 8;
pub const max_cpus = 64;

pub fn FixedList(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]T = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn append(self: *Self, value: T) !void {
            if (self.len == capacity) return error.BootInfoCapacityExceeded;
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.items[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.items[0..self.len];
        }
    };
}

pub const FdtBlob = struct {
    physical_address: u64,
    size: u32,
    tree: DeviceTree,
};

pub const Reservation = struct {
    range: PhysRange,
    kind: Kind,
    no_map: bool = false,
    reclaimable: bool = false,

    pub const Kind = enum {
        kernel,
        fdt,
        fdt_reservation,
        reserved_memory,
        boot_module,
        allocator_metadata,
        early_allocation,
    };
};

pub const BootModule = struct {
    range: PhysRange,
    used_size: u64,
    kind: Kind,

    pub const Kind = enum {
        kernel_elf,
        filesystem,
    };
};

pub const CpuDescriptor = struct {
    id: u64,
    enabled: bool,
    enable_method: EnableMethod,
    release_address: ?u64 = null,

    pub const EnableMethod = enum {
        none,
        psci,
        spin_table,
        unknown,
    };
};

pub const MemoryList = FixedList(PhysRange, max_memory_ranges);
pub const ReservationList = FixedList(Reservation, max_reservations);
pub const UsableList = FixedList(PhysRange, max_usable_ranges);
pub const ModuleList = FixedList(BootModule, max_modules);
pub const CpuList = FixedList(CpuDescriptor, max_cpus);

pub const BootInfo = struct {
    fdt: FdtBlob,
    memory: MemoryList,
    reserved: ReservationList,
    usable: UsableList,
    modules: ModuleList,
    cpus: CpuList,
    boot_cpu_id: u64,
    allocator_metadata: PhysRange,

    pub fn totalMemoryBytes(self: *const BootInfo) u64 {
        var total: u64 = 0;
        for (self.memory.constSlice()) |range| total += range.size();
        return total;
    }

    pub fn totalUsableBytes(self: *const BootInfo) u64 {
        var total: u64 = 0;
        for (self.usable.constSlice()) |range| total += range.size();
        return total;
    }
};

pub const Builder = struct {
    fdt: FdtBlob,
    memory: MemoryList = .{},
    reserved: ReservationList = .{},
    usable: UsableList = .{},
    modules: ModuleList = .{},
    cpus: CpuList = .{},
    boot_cpu_id: u64,
    allocator_metadata: ?PhysRange = null,

    pub fn init(fdt: FdtBlob, boot_cpu_id: u64) Builder {
        return .{ .fdt = fdt, .boot_cpu_id = boot_cpu_id };
    }

    pub fn addMemory(self: *Builder, range: PhysRange) !void {
        if (try range.alignedInward(page_size)) |aligned| try self.memory.append(aligned);
    }

    pub fn addReservation(
        self: *Builder,
        range: PhysRange,
        kind: Reservation.Kind,
        no_map: bool,
        reclaimable: bool,
    ) !void {
        try self.reserved.append(.{
            .range = try range.alignedOutward(page_size),
            .kind = kind,
            .no_map = no_map,
            .reclaimable = reclaimable,
        });
    }

    pub fn addModule(self: *Builder, module: BootModule) !void {
        try self.modules.append(module);
        try self.addReservation(module.range, .boot_module, false, false);
    }

    pub fn normalize(self: *Builder) !void {
        sortRanges(self.memory.slice());
        mergeMemory(&self.memory);
        try self.rebuildUsable();
    }

    pub fn carveAllocatorMetadata(self: *Builder, size: u64) !PhysRange {
        if (self.allocator_metadata != null) return error.AllocatorMetadataAlreadyReserved;
        const aligned_size = try ranges.alignUp(size, page_size);
        for (self.usable.constSlice()) |available| {
            if (available.size() < aligned_size) continue;
            const carved = PhysRange{ .start = available.start, .end = available.start + aligned_size };
            try self.addReservation(carved, .allocator_metadata, false, false);
            self.allocator_metadata = carved;
            try self.rebuildUsable();
            return carved;
        }
        return error.NoAllocatorMetadataRange;
    }

    pub fn finalize(self: *const Builder) !BootInfo {
        return .{
            .fdt = self.fdt,
            .memory = self.memory,
            .reserved = self.reserved,
            .usable = self.usable,
            .modules = self.modules,
            .cpus = self.cpus,
            .boot_cpu_id = self.boot_cpu_id,
            .allocator_metadata = self.allocator_metadata orelse return error.MissingAllocatorMetadata,
        };
    }

    fn rebuildUsable(self: *Builder) !void {
        var current: UsableList = .{};
        for (self.memory.constSlice()) |memory| try current.append(memory);

        for (self.reserved.constSlice()) |reservation| {
            var next: UsableList = .{};
            for (current.constSlice()) |available| {
                if (!available.overlaps(reservation.range)) {
                    try next.append(available);
                    continue;
                }
                if (available.start < reservation.range.start) {
                    try next.append(.{
                        .start = available.start,
                        .end = @min(available.end, reservation.range.start),
                    });
                }
                if (reservation.range.end < available.end) {
                    try next.append(.{
                        .start = @max(available.start, reservation.range.end),
                        .end = available.end,
                    });
                }
            }
            current = next;
        }

        sortRanges(current.slice());
        self.usable = current;
    }
};

fn sortRanges(items: []PhysRange) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const value = items[i];
        var j = i;
        while (j > 0 and items[j - 1].start > value.start) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = value;
    }
}

fn mergeMemory(memory: *MemoryList) void {
    if (memory.len < 2) return;
    var output: usize = 0;
    for (memory.items[1..memory.len]) |range| {
        const previous = &memory.items[output];
        if (range.start <= previous.end) {
            previous.end = @max(previous.end, range.end);
        } else {
            output += 1;
            memory.items[output] = range;
        }
    }
    memory.len = output + 1;
}

test "reservations split and trim usable memory" {
    var builder: Builder = undefined;
    builder.memory = .{};
    builder.reserved = .{};
    builder.usable = .{};
    builder.modules = .{};
    builder.cpus = .{};
    builder.boot_cpu_id = 0;
    builder.allocator_metadata = null;
    try builder.addMemory(try PhysRange.fromStartSize(0x1000, 0x9000));
    try builder.addReservation(try PhysRange.fromStartSize(0x4001, 0x1ffe), .kernel, false, false);
    try builder.normalize();
    try std.testing.expectEqualSlices(PhysRange, &.{
        .{ .start = 0x1000, .end = 0x4000 },
        .{ .start = 0x6000, .end = 0xa000 },
    }, builder.usable.constSlice());
}

test "allocator metadata is carved from usable memory" {
    var builder: Builder = undefined;
    builder.memory = .{};
    builder.reserved = .{};
    builder.usable = .{};
    builder.modules = .{};
    builder.cpus = .{};
    builder.boot_cpu_id = 0;
    builder.allocator_metadata = null;
    try builder.addMemory(try PhysRange.fromStartSize(0x1000, 0x10000));
    try builder.normalize();
    const metadata = try builder.carveAllocatorMetadata(1);
    try std.testing.expectEqual(PhysRange{ .start = 0x1000, .end = 0x2000 }, metadata);
    try std.testing.expectEqualSlices(PhysRange, &.{
        .{ .start = 0x2000, .end = 0x11000 },
    }, builder.usable.constSlice());
}
