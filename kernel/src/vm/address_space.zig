//! Machine-independent virtual address-space ownership.
//!
//! Region policy, backing objects, and fault handling do not exist yet. This
//! type establishes only the ownership seam: an address space contains one
//! machine translation map and never handles architecture descriptors itself.

const mmu = @import("../arch/mmu.zig");

pub const AddressSpace = struct {
    translation_map: mmu.TranslationMap,
};
