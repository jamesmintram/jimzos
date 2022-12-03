const page_frame_manager = @import("vm/page_frame_manager.zig");
//const BumpAllocator = page_frame_manager.BumpAllocator;

var page_allocator: page_frame_manager.BumpAllocator = undefined;

// Make a page frame
pub fn get_page_frame_manager() *page_frame_manager.BumpAllocator {
    //ASSERT INITED?
    return &page_allocator;
}

pub fn init() void {
    //init page frame manager
    page_allocator = page_frame_manager.BumpAllocator.init();
}
