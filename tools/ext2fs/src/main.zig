const std = @import("std");
const ext2 = @import("ext2");

// Doc: https://www.nongnu.org/ext2-doc/ext2.html#s-magic

// FIXME: What do we pass in here? Look at elf+dwarf parser for inspiration?
pub fn dumpInfo(fs: *ext2.FS) void {
    std.log.info("Magic {} 0x{X}", .{ @offsetOf(ext2.Ext2_SuperBlock, "s_magic"), fs.super_block.s_magic });
    //kprint.write("Dump out info for ext2 drive here\r");
}

pub fn main() anyerror!void {
    std.log.info("Inspect an ext2 image", .{});

    const fname = "test1.img";

    var f = std.fs.cwd().openFile(fname, std.fs.File.OpenFlags{ .read = true }) catch {
        std.log.err("Error opening file: {s}", .{fname});
        return;
    };

    var fs = try ext2.FS.read(f);

    dumpInfo(&fs);

    // ext2.std.log.info("All your codebase are belong to us.", .{});
    //TODO: Load a
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
