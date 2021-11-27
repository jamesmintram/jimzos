pub const Ext2_DirectoryEntry = extern struct {
    inode: u32,
    rec_len: u16,
    name_len: u8,
    file_type: u8,
    name: [255]u8,
};

pub const Ext2_InodeTableEntry = extern struct {
    i_mode: u16,
    i_uid: u16,
    i_size: u32,
    i_atime: u32,
    i_ctime: u32,
    i_mtime: u32,
    i_dtime: u32,
    i_gid: u16,
    i_links_count: u16,
    i_blocks: u32,
    i_flags: u32,
    i_osd1: u32,

    i_block: [12]u32,
    i_block_indirect: u32,
    i_block_double_indirect: u32,
    i_block_triple_indirect: u32,

    i_generation: u32,
    i_file_acl: u32,
    i_dir_acl: u32,
    i_faddr: u32,
    i_osd2: [12]u8,
};

pub const Ext2_BlockGroupDescriptor = extern struct {
    bg_block_bitmap: u32,
    bg_inode_bitmap: u32,
    bg_inode_table: u32,
    bg_free_blocks_count: u16,
    bg_free_inodes_count: u16,

    bg_used_dirs_count: u16,
    bg_pad: u16,
    bg_reserved: [12]u8,
};

pub const Ext2_SuperBlock = extern struct {
    s_inodes_count: u32,
    s_blocks_count: u32,
    s_r_blocks_count: u32,

    s_free_blocks_count: u32,
    s_free_inodes_count: u32,

    s_first_data_block: u32,
    s_log_block_size: u32,

    s_log_frag_size: u32,
    s_blocks_per_group: u32,
    s_frags_per_group: u32,

    s_inodes_per_group: u32,

    s_mtime: u32,
    s_wtime: u32,

    s_mnt_count: u16,
    s_max_mnt_count: u16,

    s_magic: u16, //0xEF53

    s_state: u16,
    s_errors: u16,
    s_minor_rev_level: u16,

    s_lastchecK: u32,
    s_checkinterval: u32,
    s_creator_os: u32,
    s_rev_level: u32,

    s_def_resuid: u16,
    s_def_resgid: u16,

    pub fn block_size(self: *const Ext2_SuperBlock) u32 {
        return @intCast(u32, 1024) << @intCast(u4, self.s_log_block_size);
    }

    pub fn block_index_for_block_group_descriptor(self: *const Ext2_SuperBlock, block_group_index: u32) u32 {
        return self.s_first_data_block + block_group_index;
    }

    pub fn block_offset_for_block_group_descriptor(self: *const Ext2_SuperBlock, block_index: u32) u32 {
        return block_index * self.block_size();
    }
};

pub const FS = struct {
    //FIXME: Remove parse_source: anytype param
    pub fn superblock(self: *const FS, parse_source: anytype) !Ext2_SuperBlock {
        _ = self;

        //FIXME: Improve this, can we write directly into the struct?
        var super_block_buf: [@sizeOf(Ext2_SuperBlock)]u8 align(@alignOf(Ext2_SuperBlock)) = undefined;
        try parse_source.seekableStream().seekTo(1024);
        try parse_source.reader().readNoEof(&super_block_buf);
        var super_block = @ptrCast(*const Ext2_SuperBlock, &super_block_buf);

        //FIXME: Pass in an *out* param?
        return super_block.*;
    }

    //FIXME: Remove parse_source: anytype param
    pub fn block_descriptor_at(self: *const FS, parse_source: anytype, block_group_index: u32) !Ext2_BlockGroupDescriptor {
        //FIXME: Assert that block_group_index > 0 (as zero is superblock) (TEST)

        var super_block = try self.superblock(parse_source);
        var block_index = super_block.block_index_for_block_group_descriptor(block_group_index);

        //FIXME: Assert that block_index < self.s_blocks_count (TEST)

        var block_position = super_block.block_offset_for_block_group_descriptor(block_index);

        //FIXME: Improve this, can we write directly into the struct?
        var block_group_descriptor_buf: [@sizeOf(Ext2_BlockGroupDescriptor)]u8 align(@alignOf(Ext2_BlockGroupDescriptor)) = undefined;
        try parse_source.seekableStream().seekTo(block_position);
        try parse_source.reader().readNoEof(&block_group_descriptor_buf);
        var block_group_descriptor = @ptrCast(*const Ext2_BlockGroupDescriptor, &block_group_descriptor_buf);

        //FIXME: Pass in an *out* param?
        return block_group_descriptor.*;
    }

    pub fn mount(parse_source: anytype) !FS {
        _ = parse_source;
        return @as(FS, .{});
    }
};