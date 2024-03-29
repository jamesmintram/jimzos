// Doc: https://www.nongnu.org/ext2-doc/ext2.html#s-magic
//      https://uranus.chrysocome.net/explore2fs/es2fs.htm
//      http://www.science.unitn.it/~fiorella/guidelinux/tlk/node95.html

pub const EXT2_FT_UNKNOWN = 0;
pub const EXT2_FT_REG_FILE = 1;
pub const EXT2_FT_DIR = 2;
pub const EXT2_FT_CHRDEV = 3;
pub const EXT2_FT_BLKDEV = 4;
pub const EXT2_FT_FIFO = 5;
pub const EXT2_FT_SOCK = 6;
pub const EXT2_FT_SYMLINK = 7;

pub const Ext2_DirectoryEntry = extern struct {
    inode: u32, // 0 == not used
    record_length: u16, // offset to the next record entry
    name_length: u8, // can never be move than rec_len - 8
    file_type: u8, // File type EXT2_FT_
    name: [*]u8,
};

pub const EXT2_S_IFSOCK = 0xC000; // socket
pub const EXT2_S_IFLNK = 0xA000; //	symbolic link
pub const EXT2_S_IFREG = 0x8000; //	regular file
pub const EXT2_S_IFBLK = 0x6000; //	block device
pub const EXT2_S_IFDIR = 0x4000; //	directory
pub const EXT2_S_IFCHR = 0x2000; //	character device
pub const EXT2_S_IFIFO = 0x1000; //	fifo

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

    pub fn block_group_count(self: *const Ext2_SuperBlock) u32 {
        return self.s_blocks_count / self.s_blocks_per_group;
    }

    pub fn block_group_size(self: *const Ext2_SuperBlock) u32 {
        return self.s_blocks_per_group * self.block_size();
    }

    pub fn block_size(self: *const Ext2_SuperBlock) u32 {
        return @intCast(u32, 1024) << @intCast(u4, self.s_log_block_size);
    }

    pub fn block_index_for_block_group_descriptor(self: *const Ext2_SuperBlock, block_group_index: u32) u32 {
        //FIXME +1 is important as the block descriptor - need to explain why
        // @import("std").log.info("block_index_for_block_group_descriptor:: {} {} {}", .{
        //     self.s_first_data_block,
        //     self.s_blocks_per_group,
        //     block_group_index,
        // });
        return self.s_first_data_block + (self.s_blocks_per_group * block_group_index) + 1;
    }

    pub fn offset_for_block_index(self: *const Ext2_SuperBlock, block_index: u32) u32 {
        return block_index * self.block_size();
    }

    pub fn inode_at(self: *const Ext2_SuperBlock, parse_source: anytype, inode: u32) !Ext2_InodeTableEntry {
        // FIXME: Validate some inode_at stuff
        var block_for_inode = (inode - 1) / self.s_inodes_per_group;
        var inode_index = (inode - 1) % self.s_inodes_per_group;

        var block_descriptor = try self.block_descriptor_at(parse_source, block_for_inode);
        return try self.inode_table_at(parse_source, &block_descriptor, inode_index);
    }

    pub fn inode_table_at(self: *const Ext2_SuperBlock, parse_source: anytype, block_descriptor: *const Ext2_BlockGroupDescriptor, inode_index: u32) !Ext2_InodeTableEntry {
        // FIXME: Verify inode >= 1 OR error
        // FIXME: Verify inode_index <= self.s_inodes_per_group OR error
        var inode_position = self.offset_for_block_index(block_descriptor.bg_inode_table) + @sizeOf(Ext2_InodeTableEntry) * inode_index;

        //FIXME: Improve this, can we write directly into the struct?
        var inode_table_entry_buf: [@sizeOf(Ext2_InodeTableEntry)]u8 align(@alignOf(Ext2_InodeTableEntry)) = undefined;
        try parse_source.seekableStream().seekTo(inode_position);
        try parse_source.reader().readNoEof(&inode_table_entry_buf);
        var inode_table_entry = @ptrCast(*const Ext2_InodeTableEntry, &inode_table_entry_buf);

        //FIXME: Pass in an *out* param?
        return inode_table_entry.*;
    }

    //FIXME: Remove parse_source: anytype param
    pub fn block_descriptor_at(self: *const Ext2_SuperBlock, parse_source: anytype, block_group_index: u32) !Ext2_BlockGroupDescriptor {
        // @import("std").log.info("block_descriptor_at:: {}", .{block_group_index});

        //FIXME: Assert that block_group_index > 0 (as zero is superblock) (TEST)
        var block_index = self.block_index_for_block_group_descriptor(block_group_index);
        // @import("std").log.info("block_descriptor_at::block_index {}", .{block_index});

        //FIXME: Assert that block_index < self.s_blocks_count (TEST)

        var block_position = self.offset_for_block_index(block_index);

        // @import("std").log.info("block_descriptor_at::block_position {}", .{block_position});

        //FIXME: Improve this, can we write directly into the struct?
        var block_group_descriptor_buf: [@sizeOf(Ext2_BlockGroupDescriptor)]u8 align(@alignOf(Ext2_BlockGroupDescriptor)) = undefined;
        try parse_source.seekableStream().seekTo(block_position);
        try parse_source.reader().readNoEof(&block_group_descriptor_buf);
        var block_group_descriptor = @ptrCast(*const Ext2_BlockGroupDescriptor, &block_group_descriptor_buf);

        //FIXME: Pass in an *out* param?
        return block_group_descriptor.*;
    }
};

pub fn DirectoryEntryIterator(ParseSource: anytype) type {
    return struct {
        parse_source: ParseSource,
        position: u32, // Position of the next entry in the filesystem

        current: Ext2_DirectoryEntry = undefined,
        current_name_pos: u32 = 0,
        current_name: [255:0]u8 = undefined,

        super_block: Ext2_SuperBlock, //TODO: Change to a ref

        // Lazily reads the filename. Laziness achieved by setting the
        // current_name[0] = 0 to signify the value has not yet been set.
        pub fn name(self: *@This()) [*:0]u8 {
            const name_len = self.current.name_length;

            if (self.current_name[0] == 0 and name_len > 0) {
                self.parse_source.seekableStream().seekTo(self.current_name_pos) catch {
                    self.current_name[0] = 0;
                    return &self.current_name;
                };
                self.parse_source.reader().readNoEof(self.current_name[0..name_len]) catch {
                    self.current_name[0] = 0;
                    return &self.current_name;
                };

                self.current_name[name_len] = 0;
            }

            return &self.current_name;
        }

        pub fn file_type(self: *@This()) !u8 {
            if (self.super_block.s_rev_level > 0) return self.current.file_type;

            var inode = try self.super_block.inode_at(self.parse_source, self.current.inode);

            // TODO: Map other types of file
            if (inode.i_mode & EXT2_S_IFREG != 0) return EXT2_FT_REG_FILE;
            if (inode.i_mode & EXT2_S_IFDIR != 0) return EXT2_FT_DIR;

            // @import("std").log.info("Unknown file_type {X}", .{inode.i_mode});

            return 0;
        }

        pub fn next(self: *@This()) !?*Ext2_DirectoryEntry {
            // FIXME: Executes with the current values on return.. is this weird?
            defer self.position += self.current.record_length;

            // @import("std").log.info("READ ENTRY: {X}", .{self.position});

            var directory_entry_buf: [@sizeOf(Ext2_DirectoryEntry)]u8 align(@alignOf(Ext2_DirectoryEntry)) = undefined;
            try self.parse_source.seekableStream().seekTo(self.position);
            try self.parse_source.reader().readNoEof(&directory_entry_buf); //FIXME: Too Long (Shouldn't read the name ptr)
            var directory_entry = @ptrCast(*const Ext2_DirectoryEntry, &directory_entry_buf);

            // Reset the current name
            self.current_name[0] = 0;
            self.current = directory_entry.*;
            self.current_name_pos = self.position + @offsetOf(Ext2_DirectoryEntry, "name");

            // FIXME: Ternery?
            if (self.current.inode == 0) return null;
            return &self.current;
        }
    };
}

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

    pub fn directory_entry_iterator(self: *const FS, parse_source: anytype, inode: *Ext2_InodeTableEntry) !DirectoryEntryIterator(@TypeOf(parse_source)) {
        var super_block = try self.superblock(parse_source);

        // FIXME: How to deal with the filename? When to read it and where to place it? file_name(dir_entry)??
        var block_idx = inode.i_block[0];
        var directory_entry_position = super_block.offset_for_block_index(block_idx);

        var directory_entry_buf: [@sizeOf(Ext2_DirectoryEntry)]u8 align(@alignOf(Ext2_DirectoryEntry)) = undefined;
        try parse_source.seekableStream().seekTo(directory_entry_position);
        try parse_source.reader().readNoEof(&directory_entry_buf);
        var directory_entry = @ptrCast(*const Ext2_DirectoryEntry, &directory_entry_buf);

        return DirectoryEntryIterator(@TypeOf(parse_source)){
            .parse_source = parse_source,
            .position = directory_entry_position,
            .current = directory_entry.*,
            .super_block = super_block,
        };
    }

    pub fn mount(parse_source: anytype) !FS {
        _ = parse_source;
        return @as(FS, .{});
    }
};
