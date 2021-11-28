const std = @import("std");
const ext2 = @import("ext2");

// FIXME: What do we pass in here? Look at elf+dwarf parser for inspiration?
pub fn printSuperBlock(super_block: *const ext2.Ext2_SuperBlock) void {
    std.log.info("FS Info:", .{});
    std.log.info("\tMagic                  0x{X}", .{super_block.s_magic});
    std.log.info("\tNumber of block groups {}", .{super_block.block_group_count()});
    std.log.info("\tBlock size             {}", .{super_block.block_size()});
    std.log.info("\tRevsion:               {}.{}", .{ super_block.s_rev_level, super_block.s_minor_rev_level });

    std.log.info("\ts_blocks_count         {}", .{super_block.s_blocks_count});
    std.log.info("\ts_first_data_block     {}", .{super_block.s_first_data_block});
    std.log.info("\ts_blocks_per_group     {}", .{super_block.s_blocks_per_group});

    std.log.info("\ts_inodes_per_group     {}", .{super_block.s_inodes_per_group});
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

pub fn printInodeTableEntry(inode: *const ext2.Ext2_InodeTableEntry) void {
    std.log.info("Inode Table Entry:", .{});
    std.log.info("\ti_mode:                {X:0>4}", .{inode.i_mode});
    std.log.info("\ti_size:                {}", .{inode.i_size});
    std.log.info("\ti_atime:               {}", .{inode.i_atime});
    std.log.info("\ti_ctime:               {}", .{inode.i_ctime});
    std.log.info("\ti_mtime:               {}", .{inode.i_mtime});
    std.log.info("\ti_dtime:               {}", .{inode.i_dtime});
    std.log.info("\ti_gid:                 {}", .{inode.i_gid});

    std.log.info("\ti_links_count:         {}", .{inode.i_links_count});
    std.log.info("\ti_blocks:              {}", .{inode.i_blocks});

    std.log.info("\ti_block[0]:            {X}", .{inode.i_block[0]});
    std.log.info("\ti_block[1]:            {X}", .{inode.i_block[1]});
    std.log.info("\ti_block[2]:            {X}", .{inode.i_block[2]});
    std.log.info("\ti_block[3]:            {X}", .{inode.i_block[3]});
    std.log.info("\ti_block[4]:            {X}", .{inode.i_block[4]});
    std.log.info("\ti_block[5]:            {X}", .{inode.i_block[5]});
}

pub fn printDirectoryEntry(directory_entry: *const ext2.Ext2_DirectoryEntry) void {
    std.log.info("Directory Entry:", .{});
    std.log.info("\tinode:                  {}", .{directory_entry.inode});
    std.log.info("\trecord_length:          {}", .{directory_entry.record_length});
    std.log.info("\tname_length:            {}", .{directory_entry.name_length});
    std.log.info("\tfile_type:              {X}", .{directory_entry.file_type});
}

// FIXME: Fails when s_first_data_block == 0 (file: test1_4kb.img)
// FIXME: Division by zero when calculating block_group_count

pub fn main() anyerror!void {
    std.log.info("Inspect an ext2 image (All your files are belong to us.)", .{});

    const fname = "data/test3.img";

    var f = std.fs.cwd().openFile(fname, std.fs.File.OpenFlags{ .read = true }) catch {
        std.log.err("Error opening file: {s}", .{fname});
        return;
    };

    var fs = try ext2.FS.mount(f);

    var super_block = try fs.superblock(f);

    printSuperBlock(&super_block);

    var block_descriptor = try super_block.block_descriptor_at(f, 0);
    printBlockGroupDescriptor(&block_descriptor);

    // TODO: How to handle sparse superblocks
    // FIXME: Change magic number from 2 => Ext2RootInodeIndex

    var inode = try super_block.inode_table_at(f, &block_descriptor, 1); // 1 is reserved as root directory
    printInodeTableEntry(&inode);

    var directory_entry_iterator = try fs.directory_entry_iterator(f, &inode);

    while (try directory_entry_iterator.next()) |_| {
        //FIXME: Should pass in a struct containg meta + dir entry
        //printDirectoryEntry(dir_entry);
        switch (try directory_entry_iterator.file_type()) {
            ext2.EXT2_FT_DIR => std.log.info("{s}/", .{directory_entry_iterator.name()}),
            ext2.EXT2_FT_REG_FILE => std.log.info("{s}", .{directory_entry_iterator.name()}),
            else => |v| std.log.info("UNKNOWN {}: {s}", .{ v, directory_entry_iterator.name() }),
        }
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
