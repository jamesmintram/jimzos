pub const Entry = u64;

pub const page_shift: u6 = 12;
pub const page_size: usize = 1 << page_shift;
pub const table_size: usize = page_size;
pub const entries_per_table: usize = 512;
pub const index_mask: usize = entries_per_table - 1;

pub const level_count: usize = 4;
pub const level_0_shift: u6 = 39;
pub const level_1_shift: u6 = 30;
pub const level_2_shift: u6 = 21;
pub const level_3_shift: u6 = page_shift;
pub const virtual_address_bits: u7 = 48;
pub const tcr_size_offset: u6 = 64 - virtual_address_bits;

pub const table_address_mask: Entry = 0x0000_ffff_ffff_f000;

pub const descriptor_table_or_page: Entry = 0b11;
pub const access_flag: Entry = 1 << 10;
pub const outer_shareable: Entry = 2 << 8;
pub const inner_shareable: Entry = 3 << 8;
pub const attr_index_normal: Entry = 0 << 2;
pub const attr_index_device: Entry = 1 << 2;

comptime {
    if (table_size != entries_per_table * @sizeOf(Entry)) {
        @compileError("AArch64 translation table geometry is inconsistent");
    }
}
