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
};

pub const FS = struct {
    super_block: Ext2_SuperBlock = undefined,

    pub fn read(parse_source: anytype) !FS {
        var super_block_buf: [@sizeOf(Ext2_SuperBlock)]u8 align(@alignOf(Ext2_SuperBlock)) = undefined;

        // Read superblock from stream
        try parse_source.seekableStream().seekTo(1024);
        try parse_source.reader().readNoEof(&super_block_buf);

        var super_block = @ptrCast(*const Ext2_SuperBlock, &super_block_buf);

        return @as(FS, .{ .super_block = super_block.* });
    }
};
