const std = @import("std");
const ext2 = @import("ext2");

// Doc: https://www.nongnu.org/ext2-doc/ext2.html#s-magic
//      https://uranus.chrysocome.net/explore2fs/es2fs.htm
//      http://www.science.unitn.it/~fiorella/guidelinux/tlk/node95.html

// FIXME: What do we pass in here? Look at elf+dwarf parser for inspiration?
pub fn printSuperBlock(super_block: *const ext2.Ext2_SuperBlock) void {
    std.log.info("FS Info:", .{});
    std.log.info("\tMagic                  0x{X}", .{super_block.s_magic});
    std.log.info("\tNumber of block groups {}", .{super_block.block_group_count()});
    std.log.info("\tBlock size             {}", .{super_block.block_size()});

    std.log.info("\ts_blocks_count         {}", .{super_block.s_blocks_count});
    std.log.info("\ts_first_data_block     {}", .{super_block.s_first_data_block});
    std.log.info("\ts_blocks_per_group     {}", .{super_block.s_blocks_per_group});
}

pub fn printBlockGroupDescriptor(block_group_descriptor: *const ext2.Ext2_BlockGroupDescriptor) void {

    // TODO: Move this into a generic "format" fn and into the Ext2 lib, then info("{}", .{block_group_descriptor})
    std.log.info("Block Desc Group:", .{});
    std.log.info("\tblock_bitmap:          {}", .{block_group_descriptor.bg_block_bitmap});
    std.log.info("\tbg_inode_bitmap:       {}", .{block_group_descriptor.bg_inode_bitmap});
    std.log.info("\tbg_inode_table         {}", .{block_group_descriptor.bg_inode_table});
    std.log.info("\tbg_free_blocks_count:  {}", .{block_group_descriptor.bg_free_blocks_count});
    std.log.info("\tbg_free_inodes_count:  {}", .{block_group_descriptor.bg_free_inodes_count});
    std.log.info("\tbg_used_dirs_count:    {}", .{block_group_descriptor.bg_used_dirs_count});
}

// FIXME: Fails when s_first_data_block == 0 (file: test1_4kb.img)

pub fn main() anyerror!void {
    std.log.info("Inspect an ext2 image (All your files are belong to us.)", .{});

    const fname = "data/test1.img";

    var f = std.fs.cwd().openFile(fname, std.fs.File.OpenFlags{ .read = true }) catch {
        std.log.err("Error opening file: {s}", .{fname});
        return;
    };

    var fs = try ext2.FS.mount(f);

    var super_block = try fs.superblock(f);

    printSuperBlock(&super_block);

    std.log.info("Offset: {}", .{super_block.block_index_for_block_group_descriptor(1)});
    printBlockGroupDescriptor(&try fs.block_descriptor_at(f, 1));

    if (super_block.block_group_count() > 1) {
        std.log.info("Offset: {}", .{super_block.block_index_for_block_group_descriptor(2)});
        printBlockGroupDescriptor(&try fs.block_descriptor_at(f, 2));
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
