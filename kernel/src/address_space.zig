

pub const AddressSpace = struct {

};

pub fn create_default_address_space(allocator : *Allocator) *AddressSpace {
    return undefined;
}

pub fn map_range(as : *AddressSpace) void {
    //Split, merge etc
}
pub fn unmap_range(as : *AddressSpace) void {
    //Split, merge etc
}

pub fn update_page_table(as : AddressSpace) void {
    //TODO Pass in a pointer? or something to output to
}
