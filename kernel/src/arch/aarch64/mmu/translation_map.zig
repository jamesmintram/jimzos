//! Installed AArch64 translation-map ownership and root activation.
//!
//! This is the post-bootstrap representation seen above the AArch64 MMU
//! boundary. It intentionally exposes no dynamic mapping operations yet.

const page_table = @import("page_table.zig");

pub const Kind = enum {
    kernel,
    user,
};

pub const TranslationMap = struct {
    kind: Kind,
    root_physical: u64,
    table_pages: usize,

    pub fn init(kind: Kind, root_physical: u64, table_pages: usize) !TranslationMap {
        if (root_physical == 0 or root_physical % page_table.page_size != 0) {
            return error.InvalidTranslationRoot;
        }
        if (table_pages == 0) return error.EmptyTranslationMap;
        return .{
            .kind = kind,
            .root_physical = root_physical,
            .table_pages = table_pages,
        };
    }
};

pub const InstalledMaps = struct {
    kernel: TranslationMap,
    idle_user: TranslationMap,

    pub fn totalTablePages(self: InstalledMaps) usize {
        return self.kernel.table_pages + self.idle_user.table_pages;
    }
};

var current_maps: InstalledMaps = undefined;
var maps_installed = false;

pub fn install(maps: InstalledMaps) !void {
    if (maps_installed) return error.TranslationMapsAlreadyInstalled;
    if (maps.kernel.kind != .kernel or maps.idle_user.kind != .user) {
        return error.InvalidTranslationMapKinds;
    }

    switchRoots(maps.kernel.root_physical, maps.idle_user.root_physical);
    current_maps = maps;
    maps_installed = true;
}

pub fn current() *const InstalledMaps {
    if (!maps_installed) @panic("translation maps used before installation");
    return &current_maps;
}

fn switchRoots(high_root: u64, low_root: u64) void {
    asm volatile (
        \\ dsb ishst
        \\ msr ttbr1_el1, %[high]
        \\ msr ttbr0_el1, %[low]
        \\ isb
        \\ tlbi vmalle1
        \\ dsb ish
        \\ isb
        :
        : [high] "r" (@as(usize, @intCast(high_root))),
          [low] "r" (@as(usize, @intCast(low_root))),
        : .{ .memory = true });
}
