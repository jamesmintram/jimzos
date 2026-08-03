//! Statically selected machine MMU boundary.
//!
//! JimZOS currently targets only AArch64, so this is a compile-time re-export
//! rather than a runtime interface.

const aarch64 = @import("aarch64/mmu/translation_map.zig");
const layout = @import("aarch64/mmu/layout.zig");

pub const TranslationMap = aarch64.TranslationMap;
pub const MapOptions = aarch64.MapOptions;
pub const MemoryType = aarch64.MemoryType;
pub const mapRange = aarch64.mapRange;
pub const kernel_direct_map_base = layout.kernel_direct_map_base;
pub const physicalToVirtual = layout.physicalToVirtual;
pub const virtualToPhysical = layout.virtualToPhysical;
