const std = @import("std");
const DeviceTree = @import("DeviceTree");
const ranges = @import("phys_range");

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

pub const ReservationRequirement = struct {
    size: u64,
    alignment: u64 = page_size,
};

pub const ReservationRequirementFn = fn (
    memory: []const PhysRange,
) anyerror!ReservationRequirement;

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

    pub fn init(fdt: FdtBlob, boot_cpu_id: u64) Builder {
        return .{ .fdt = fdt, .boot_cpu_id = boot_cpu_id };
    }

    pub fn addMemory(self: *Builder, range: PhysRange) !void {
        if (try range.alignedInward(page_size)) |aligned| {
            try self.memory.append(aligned);
        }
    }

    pub fn addReservation(
        self: *Builder,
        range: PhysRange,
        kind: Reservation.Kind,
        no_map: bool,
        reclaimable: bool,
    ) !void {
        if (kind == .allocator_metadata) return error.BuilderManagedReservationKind;
        try self.appendReservation(range, kind, no_map, reclaimable);
    }

    fn appendReservation(
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

    fn normalize(self: *Builder) !void {
        sortRanges(self.memory.slice());
        mergeMemory(&self.memory);
        try self.rebuildUsable();
    }

    fn reserveFirstFit(
        self: *Builder,
        size: u64,
        alignment: u64,
        kind: Reservation.Kind,
    ) !PhysRange {
        if (size == 0) return error.EmptyReservation;
        if (alignment < page_size or !std.math.isPowerOfTwo(alignment)) {
            return error.InvalidReservationAlignment;
        }

        const aligned_size = try ranges.alignUp(size, page_size);
        for (self.usable.constSlice()) |available| {
            const start = try ranges.alignUp(available.start, alignment);
            if (start >= available.end or aligned_size > available.end - start) continue;

            const reserved = PhysRange{ .start = start, .end = start + aligned_size };
            try self.appendReservation(reserved, kind, false, false);
            try self.rebuildUsable();
            return reserved;
        }
        return error.NoUsableReservationRange;
    }

    /// Produce a snapshot after canonicalizing fixed inputs and placing
    /// builder-managed reservations that depend on the final memory layout.
    pub fn finish(
        self: *const Builder,
        comptime metadata_requirement: ReservationRequirementFn,
    ) anyerror!BootInfo {
        var snapshot = self.*;
        try snapshot.normalize();

        const requirement = try metadata_requirement(snapshot.memory.constSlice());
        const allocator_metadata = try snapshot.reserveFirstFit(
            requirement.size,
            requirement.alignment,
            .allocator_metadata,
        );

        return .{
            .fdt = snapshot.fdt,
            .memory = snapshot.memory,
            .reserved = snapshot.reserved,
            .usable = snapshot.usable,
            .modules = snapshot.modules,
            .cpus = snapshot.cpus,
            .boot_cpu_id = snapshot.boot_cpu_id,
            .allocator_metadata = allocator_metadata,
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
    try builder.addMemory(try PhysRange.fromStartSize(0x1000, 0x9000));
    try builder.addReservation(try PhysRange.fromStartSize(0x4001, 0x1ffe), .kernel, false, false);
    try builder.normalize();
    try std.testing.expectEqualSlices(PhysRange, &.{
        .{ .start = 0x1000, .end = 0x4000 },
        .{ .start = 0x6000, .end = 0xa000 },
    }, builder.usable.constSlice());
}

test "finish creates reusable snapshots with late allocator metadata" {
    var builder: Builder = undefined;
    builder.memory = .{};
    builder.reserved = .{};
    builder.usable = .{};
    builder.modules = .{};
    builder.cpus = .{};
    builder.boot_cpu_id = 0;
    try builder.addMemory(try PhysRange.fromStartSize(0x1000, 0x4000));
    try builder.addMemory(try PhysRange.fromStartSize(0x5000, 0xc000));
    try std.testing.expectError(
        error.BuilderManagedReservationKind,
        builder.addReservation(
            try PhysRange.fromStartSize(0x3000, page_size),
            .allocator_metadata,
            false,
            false,
        ),
    );
    try builder.addReservation(
        try PhysRange.fromStartSize(0x1000, 0x2000),
        .kernel,
        false,
        false,
    );

    const metadata_requirement = struct {
        fn get(memory: []const PhysRange) anyerror!ReservationRequirement {
            if (memory.len != 1 or
                !std.meta.eql(memory[0], PhysRange{ .start = 0x1000, .end = 0x11000 }))
            {
                return error.MemoryNotNormalized;
            }
            return .{ .size = 1 };
        }
    }.get;
    const info = try builder.finish(metadata_requirement);
    try std.testing.expectEqual(@as(usize, 1), builder.reserved.len);
    try std.testing.expectEqual(
        PhysRange{ .start = 0x3000, .end = 0x4000 },
        info.allocator_metadata,
    );
    try std.testing.expectEqualSlices(PhysRange, &.{
        .{ .start = 0x4000, .end = 0x11000 },
    }, info.usable.constSlice());

    try builder.addModule(.{
        .range = try PhysRange.fromStartSize(0x3000, 0x2000),
        .used_size = 0x2000,
        .kind = .filesystem,
    });
    const updated_info = try builder.finish(metadata_requirement);
    try std.testing.expectEqual(@as(usize, 2), builder.reserved.len);
    try std.testing.expectEqual(@as(usize, 0), info.modules.len);
    try std.testing.expectEqual(@as(usize, 1), updated_info.modules.len);
    try std.testing.expectEqual(
        PhysRange{ .start = 0x5000, .end = 0x6000 },
        updated_info.allocator_metadata,
    );
    try std.testing.expectEqualSlices(PhysRange, &.{
        .{ .start = 0x6000, .end = 0x11000 },
    }, updated_info.usable.constSlice());
}
