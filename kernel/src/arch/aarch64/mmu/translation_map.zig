//! AArch64 translation-map ownership, mutation, and root activation.

const std = @import("std");
const builtin = @import("builtin");
const phys = @import("phys_range");
const layout = @import("layout.zig");
const page_table = @import("page_table.zig");
const table_editor = @import("table_editor.zig");
const PhysicalAllocator = @import("../../../vm/page_frame_manager.zig").PhysicalAllocator;
const RuntimeTablePageProvider = @import("table_page_provider.zig").TablePageProvider;

pub const Kind = enum {
    kernel,
    user,
};

const State = enum {
    unpublished,
    published,
    moved,
};

pub const MemoryType = page_table.MemoryType;
pub const MapOptions = page_table.MapOptions;

/// Owns one complete hardware translation hierarchy: its root and every table
/// page reachable from that root. Providers are borrowed only while creating
/// or editing the hierarchy and are never retained here.
pub const TranslationMap = struct {
    kind: Kind,
    root_physical: u64,
    table_pages: usize,
    state: State,

    const Self = @This();

    /// Create a new unpublished translation hierarchy with one empty root.
    pub fn create(kind: Kind, provider: anytype) !Self {
        const root_physical = try provider.allocateZeroed();
        if (root_physical == 0 or root_physical % page_table.page_size != 0) {
            return error.InvalidTranslationRoot;
        }
        return .{
            .kind = kind,
            .root_physical = root_physical,
            .table_pages = 1,
            .state = .unpublished,
        };
    }

    /// Populate this map using the largest descriptors permitted by alignment.
    /// This is used while constructing the initial kernel map.
    pub fn mapRange(
        self: *Self,
        provider: anytype,
        virtual_start: u64,
        physical: phys.PhysRange,
        attributes: page_table.Entry,
    ) !void {
        if (self.state == .moved) return error.TranslationMapOwnershipMoved;
        const Editor = table_editor.TableEditor(@TypeOf(provider.*));
        var editor = try Editor.init(provider, self.root_physical);
        defer self.completeEdit(editor.allocatedTablePageCount());
        try editor.mapRange(virtual_start, physical, attributes);
    }

    /// Populate this map using base-page descriptors only. This conservative
    /// mode is used for runtime device mappings because block splitting and
    /// break-before-make replacement are not implemented yet.
    pub fn mapPageRange(
        self: *Self,
        provider: anytype,
        virtual_start: u64,
        physical: phys.PhysRange,
        attributes: page_table.Entry,
    ) !void {
        if (self.state == .moved) return error.TranslationMapOwnershipMoved;
        const Editor = table_editor.TableEditor(@TypeOf(provider.*));
        var editor = try Editor.init(provider, self.root_physical);
        defer self.completeEdit(editor.allocatedTablePageCount());
        try editor.mapPageRange(virtual_start, physical, attributes);
    }

    fn completeEdit(self: *Self, allocated_table_pages: usize) void {
        self.table_pages += allocated_table_pages;
        if (self.state == .published) flushTranslations();
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
var table_allocator: *PhysicalAllocator = undefined;
var maps_installed = false;

/// Consume unpublished boot maps and move them into the canonical installed
/// storage. The source is invalidated so it cannot remain an offline alias to
/// the same physical hierarchy.
pub fn install(maps: *InstalledMaps, allocator: *PhysicalAllocator) !void {
    if (maps_installed) return error.TranslationMapsAlreadyInstalled;
    if (maps.kernel.kind != .kernel or maps.idle_user.kind != .user) {
        return error.InvalidTranslationMapKinds;
    }
    if (maps.kernel.state != .unpublished or maps.idle_user.state != .unpublished) {
        return error.TranslationMapsAlreadyPublished;
    }

    var installed = maps.*;
    installed.kernel.state = .published;
    installed.idle_user.state = .published;

    switchRoots(installed.kernel.root_physical, installed.idle_user.root_physical);
    current_maps = installed;
    table_allocator = allocator;
    maps_installed = true;

    maps.kernel = movedMap(.kernel);
    maps.idle_user = movedMap(.user);
}

pub fn current() *const InstalledMaps {
    if (!maps_installed) @panic("translation maps used before installation");
    return &current_maps;
}

/// Map base pages in the installed kernel translation map. This single-core
/// operation validates kernel policy, borrows the runtime table-page provider,
/// mutates the existing map, accounts partial progress, and flushes the TLB.
pub fn mapRange(
    virtual_start: usize,
    physical_pages: phys.PhysRange,
    options: MapOptions,
) !void {
    if (!maps_installed) return error.TranslationMapsNotInstalled;
    try validateKernelRange(virtual_start, physical_pages);
    const attributes = try page_table.kernelMappingAttributes(options);

    var provider = RuntimeTablePageProvider.init(table_allocator);
    try current_maps.kernel.mapPageRange(
        &provider,
        @intCast(virtual_start),
        physical_pages,
        attributes,
    );
}

fn validateKernelRange(virtual_start: usize, physical_pages: phys.PhysRange) !void {
    const page_size: u64 = page_table.page_size;
    if (physical_pages.start >= physical_pages.end) return error.EmptyMappingRange;
    if (virtual_start % page_table.page_size != 0 or
        physical_pages.start % page_size != 0 or
        physical_pages.end % page_size != 0)
    {
        return error.UnalignedMappingRange;
    }
    if (physical_pages.end > page_table.physical_address_limit) {
        return error.PhysicalMappingRangeOverflow;
    }

    const virtual: u64 = @intCast(virtual_start);
    if (virtual < layout.kernel_direct_map_base) return error.InvalidKernelVirtualRange;
    _ = std.math.add(u64, virtual, physical_pages.size()) catch {
        return error.VirtualMappingRangeOverflow;
    };
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

fn flushTranslations() void {
    if (builtin.cpu.arch == .aarch64) {
        asm volatile (
            \\ dsb ishst
            \\ tlbi vmalle1
            \\ dsb ish
            \\ isb
            ::: .{ .memory = true });
    }
}

fn movedMap(kind: Kind) TranslationMap {
    return .{
        .kind = kind,
        .root_physical = 0,
        .table_pages = 0,
        .state = .moved,
    };
}

const TestTablePageProvider = struct {
    const table_capacity = 8;
    const Table = [page_table.entries_per_table]page_table.Entry;

    tables: [table_capacity]Table,
    allocated: usize,

    fn init() TestTablePageProvider {
        var self: TestTablePageProvider = undefined;
        self.allocated = 0;
        @memset(std.mem.asBytes(&self.tables), 0);
        return self;
    }

    pub fn allocateZeroed(self: *TestTablePageProvider) !u64 {
        if (self.allocated == table_capacity) return error.OutOfPageTableMemory;
        const index = self.allocated;
        self.allocated += 1;
        @memset(&self.tables[index], 0);
        return (@as(u64, @intCast(index)) + 1) * page_table.page_size;
    }

    pub fn tableAt(self: *TestTablePageProvider, physical: u64) *Table {
        std.debug.assert(physical != 0 and physical % page_table.page_size == 0);
        const index: usize = @intCast(physical / page_table.page_size - 1);
        std.debug.assert(index < self.allocated);
        return &self.tables[index];
    }
};

test "translation map creates one root and accounts in-place edits" {
    var provider = TestTablePageProvider.init();
    var map = try TranslationMap.create(.kernel, &provider);

    try std.testing.expectEqual(Kind.kernel, map.kind);
    try std.testing.expectEqual(@as(u64, page_table.page_size), map.root_physical);
    try std.testing.expectEqual(@as(usize, 1), map.table_pages);
    try std.testing.expectEqual(State.unpublished, map.state);

    const virtual: u64 = 0x4000_0000;
    const physical: u64 = 0x8000_0000;
    try map.mapPageRange(
        &provider,
        virtual,
        try phys.PhysRange.fromStartSize(physical, page_table.page_size),
        page_table.normal_attributes,
    );
    try std.testing.expectEqual(@as(usize, 4), map.table_pages);
    try std.testing.expectEqual(@as(usize, 4), provider.allocated);

    try map.mapPageRange(
        &provider,
        virtual + page_table.page_size,
        try phys.PhysRange.fromStartSize(
            physical + page_table.page_size,
            page_table.page_size,
        ),
        page_table.normal_attributes,
    );
    try std.testing.expectEqual(@as(usize, 4), map.table_pages);
    try std.testing.expectEqual(@as(usize, 4), provider.allocated);
}
