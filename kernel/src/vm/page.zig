//
//
//
//
const std = @import("std");

pub const Page = struct {
    all_next : *Page,
    all_prev : *Page,

    free_next : *Page,
    free_prev : *Page,

    phys_addr : usize,
};

var sys_pages : *Page = undefined;
var sys_page_count : usize = 0;

fn add_to_freelist(page : *Page) void {

}

pub fn find_free_page() *Page {
    //FIXME this can fail
    return undefined;
}

pub fn dump(writer : *std.io.Writer) void {
    const page_memory_required = @sizeOf(Page) * sys_page_count;

    // uart.write("Page count: {}\n", .{sys_page_count});
    // uart.write("Page memory required: {}\n", .{page_memory_required / 1024 / 1024});
}

pub fn add_phys_pages(page_base : *Page, base_addr : usize, num : usize) void {
    //TODO: Assert that we have not already called this

    //page_base is allocated by the startup routine
    sys_pages = page_base;
    sys_page_count = num;

    const page_memory_required = @sizeOf(Page) * sys_page_count;
    const pages_memory_pages = (page_memory_required + 4095) / 4096;

    //Foreach page after the page_memory_pages
    // Link into the all list
    // Calculate + set the phys_addr
    // Add to the free list
}
