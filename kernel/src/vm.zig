const boot = @import("boot/boot_info.zig");
const page_frame_manager = @import("vm/page_frame_manager.zig");

var physical_allocator: page_frame_manager.PhysicalAllocator = .{};
var initialized = false;

pub fn reserveMetadata(builder: *boot.Builder) !void {
    const bytes = try page_frame_manager.PhysicalAllocator.requiredMetadataBytes(&builder.memory);
    _ = try builder.carveAllocatorMetadata(bytes);
}

pub fn init(info: *const boot.BootInfo) !void {
    if (initialized) return error.AlreadyInitialized;
    try physical_allocator.init(info);

    const one_page = physical_allocator.allocatePages(1) orelse return error.AllocatorSelfTestFailed;
    const two_pages = physical_allocator.allocatePages(2) orelse {
        try physical_allocator.releasePages(one_page, 1);
        return error.AllocatorSelfTestFailed;
    };
    try physical_allocator.releasePages(two_pages, 2);
    try physical_allocator.releasePages(one_page, 1);
    if (physical_allocator.stats().allocated_pages != 0) return error.AllocatorSelfTestFailed;

    initialized = true;
}

pub fn get_page_frame_manager() *page_frame_manager.PhysicalAllocator {
    if (!initialized) @panic("physical allocator used before initialization");
    return &physical_allocator;
}
