const std = @import("std");
const uefi = std.os.uefi;

pub fn main() uefi.Status {
    const con_out = uefi.system_table.con_out.?;

    const msg = std.unicode.utf8ToUtf16LeStringLiteral("Hello from Zig EFI!\r\n");
    _ = con_out.outputString(msg) catch {};

    while (true) {
        asm volatile ("wfe");
    }

    return .success;
}
