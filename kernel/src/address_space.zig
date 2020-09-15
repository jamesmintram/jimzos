
const ASRange = struct {
    name : *const u8 = "",
    base : usize,
    size : usize,
};

const default_as = []ASRange {
    ASRange{
        .name = ".text",
        .base = 0x10000,
        .size = 0x10000,
    },
    ASRange{
        .name = ".stack",
        .base = 0x1000000,
        .size = 0x1000000,
    },
    ASRange{
        .name = ".heap",
        .base = 0x2000000,
        .size = 0x10000000,
    },
};

pub const AddressSpace = struct {

};

pub fn create_default_address_space(allocator : *Allocator) *AddressSpace {
    //Need a way to map physical memory to where it is being used?    
    //VMO? has a linked list of all usages (ptr to head)

    return undefined;
}

pub fn handle_page_fault(as : *AddressSpace, addr : usize) void {

}

pub fn map_range(as : *AddressSpace, base : usize, size : usize) void { //TODO: Add flags for memory mapping
    //Split, merge etc
}
pub fn unmap_range(as : *AddressSpace, base : usize, size : usize) void { //TODO: Add flags for memory mapping
    //Split, merge etc
}

fn update_page_table(as : AddressSpace) void {
    //TODO Pass in a pointer? or something to output to
    //TODO How do we translate an AS into a page table efficiently? 
    //TODO: Instead of a "Funtional" approach, we can take a more imperitive style: MapFrameToVA(as, addr, frame)
    //      Could we use 64k "VNodes" as our minimum? Reducing % overhead? 64k would represent a VNode?
}
