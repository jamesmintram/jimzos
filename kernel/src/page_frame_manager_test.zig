const std = @import("std");
const ranges = @import("phys_range");
const PhysicalAllocator = @import("vm/page_frame_manager.zig").PhysicalAllocator;

test "allocator metadata sizing rounds each memory bank independently" {
    const memory = [_]ranges.PhysRange{
        .{ .start = 0x1000, .end = 0x2000 },
        .{
            .start = 0x10_0000,
            .end = 0x10_0000 + 32_767 * ranges.page_size,
        },
    };

    const requirement = try PhysicalAllocator.metadataRequirement(&memory);
    try std.testing.expectEqual(2 * ranges.page_size, requirement.size);
    try std.testing.expectEqual(ranges.page_size, requirement.alignment);
}

test "allocator metadata sizing rejects an empty memory map" {
    const memory = [_]ranges.PhysRange{};
    try std.testing.expectError(
        error.NoMemoryForAllocator,
        PhysicalAllocator.metadataRequirement(&memory),
    );
}
