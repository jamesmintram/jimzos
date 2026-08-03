//! Arm GICv3 interrupt-controller driver for AArch64.

const std = @import("std");
const cpu = @import("../cpu.zig");
const interrupt = @import("../../../interrupt.zig");
const MmioRegion = @import("../../../io/mmio_region.zig").MmioRegion;

const maximum_handlers = 32;
const default_redistributor_stride: usize = 0x2_0000;
const minimum_distributor_size: usize = 0x1_0000;
const minimum_redistributor_size: usize = 0x2_0000;
const maximum_poll_iterations: usize = 1_000_000;

const gicd_ctlr = 0x0000;
const gicd_ctlr_rwp = @as(u32, 1) << 31;

// These are the Non-secure view encodings when two Security states are in
// use, and the single-Security-state encodings used by QEMU virt. In both
// views bit 4 enables affinity routing and bit 1 enables Group 1 once
// affinity routing is active.
const gicd_ctlr_are = @as(u32, 1) << 4;
const gicd_ctlr_enable_group1 = @as(u32, 1) << 1;
const gicd_ctlr_group_enable_mask = @as(u32, 0b11);

const gicr_ctlr = 0x0000;
const gicr_typer = 0x0008;
const gicr_waker = 0x0014;
const gicr_ctlr_rwp = @as(u32, 1) << 3;
const gicr_typer_last = @as(u64, 1) << 4;
const gicr_waker_processor_sleep = @as(u32, 1) << 1;
const gicr_waker_children_asleep = @as(u32, 1) << 2;

const gicr_sgi_base = 0x1_0000;
const gicr_igroupr0 = gicr_sgi_base + 0x0080;
const gicr_isenabler0 = gicr_sgi_base + 0x0100;
const gicr_icenabler0 = gicr_sgi_base + 0x0180;
const gicr_icpendr0 = gicr_sgi_base + 0x0280;
const gicr_icactiver0 = gicr_sgi_base + 0x0380;
const gicr_ipriorityr0 = gicr_sgi_base + 0x0400;
const gicr_icfgr1 = gicr_sgi_base + 0x0c04;

const first_ppi_intid: u32 = 16;
const last_ppi_intid: u32 = 31;
const default_priority: u8 = 0x80;
const intid_mask: u64 = 0x00ff_ffff;

const icc_sre_sre = @as(u64, 1) << 0;
const icc_ctlr_eoi_mode = @as(u64, 1) << 1;

pub const Config = struct {
    distributor: MmioRegion,
    redistributors: MmioRegion,
    redistributor_stride: usize = default_redistributor_stride,
};

const HandlerTable = struct {
    entries: [maximum_handlers]Entry = undefined,
    len: usize = 0,

    const Entry = struct {
        line: u32,
        function: *const fn (*anyopaque) void,
        context: *anyopaque,

        fn invoke(self: Entry) void {
            self.function(self.context);
        }
    };

    fn establish(
        self: *HandlerTable,
        line: u32,
        function: *const fn (*anyopaque) void,
        context: *anyopaque,
    ) !void {
        if (self.find(line) != null) return error.InterruptAlreadyEstablished;
        if (self.len == self.entries.len) return error.InterruptHandlerTableFull;

        self.entries[self.len] = .{
            .line = line,
            .function = function,
            .context = context,
        };
        self.len += 1;
    }

    fn remove(self: *HandlerTable, line: u32) void {
        for (self.entries[0..self.len], 0..) |entry, index| {
            if (entry.line != line) continue;
            self.len -= 1;
            if (index != self.len) self.entries[index] = self.entries[self.len];
            return;
        }
    }

    fn find(self: *const HandlerTable, line: u32) ?Entry {
        for (self.entries[0..self.len]) |entry| {
            if (entry.line == line) return entry;
        }
        return null;
    }
};

pub const GicV3 = struct {
    distributor: MmioRegion,
    redistributor: MmioRegion,
    handlers: HandlerTable = .{},

    const Self = @This();

    /// Bring up the GIC distributor and the current PE's Redistributor and CPU
    /// interface. PSTATE.I remains untouched; the caller must keep IRQs masked
    /// until an interrupt source and the exception vector are ready.
    pub fn init(config: Config) !Self {
        try validateConfig(config);
        try prepareDistributor(config.distributor);

        const redistributor = try findRedistributor(config);
        try wakeRedistributor(redistributor);
        try initializeCpuInterface();
        try enableDistributorGroup1(config.distributor);

        return .{
            .distributor = config.distributor,
            .redistributor = redistributor,
        };
    }

    /// Provider-facing interface published by this controller's attachment.
    pub fn interruptController(self: *Self) interrupt.Controller {
        return .{
            .context = self,
            .establish_function = establishOpaque,
        };
    }

    /// Provider-facing capability for servicing the CPU's root IRQ.
    pub fn rootController(self: *Self) interrupt.RootController {
        return .{
            .context = self,
            .dispatch_function = dispatchOpaque,
        };
    }

    /// Configure and enable a standard PPI (INTIDs 16-31) for the current PE.
    /// The interrupt is assigned to Non-secure Group 1.
    fn configurePpi(self: *Self, route: interrupt.Route, priority: u8) !void {
        const intid = route.line;
        if (intid < first_ppi_intid or intid > last_ppi_intid) {
            return error.InvalidPpiIntid;
        }

        const configuration_bits: u32 = switch (route.trigger) {
            .level_high => 0,
            .edge_rising => 0b10,
            .level_low, .edge_falling => return error.UnsupportedInterruptPolarity,
        };

        const interrupt_bit = @as(u32, 1) << @as(u5, @intCast(intid));

        // Configuration registers must only be changed while the interrupt is
        // disabled. Wait for the disable to propagate before changing state.
        self.redistributor.write32(gicr_icenabler0, interrupt_bit);
        try waitRedistributorRwp(self.redistributor);

        var group = self.redistributor.read32(gicr_igroupr0);
        group |= interrupt_bit;
        self.redistributor.write32(gicr_igroupr0, group);
        if ((self.redistributor.read32(gicr_igroupr0) & interrupt_bit) == 0) {
            return error.PpiGroupConfigurationUnavailable;
        }

        const configuration_shift: u5 = @intCast((intid - first_ppi_intid) * 2);
        var configuration = self.redistributor.read32(gicr_icfgr1);
        configuration &= ~(@as(u32, 0b11) << configuration_shift);
        configuration |= configuration_bits << configuration_shift;
        self.redistributor.write32(gicr_icfgr1, configuration);

        const priority_register = gicr_ipriorityr0 + @as(usize, @intCast(intid & ~@as(u32, 3)));
        const priority_shift: u5 = @intCast((intid & 3) * 8);
        var priorities = self.redistributor.read32(priority_register);
        priorities &= ~(@as(u32, 0xff) << priority_shift);
        priorities |= @as(u32, priority) << priority_shift;
        self.redistributor.write32(priority_register, priorities);

        self.redistributor.write32(gicr_icpendr0, interrupt_bit);
        self.redistributor.write32(gicr_icactiver0, interrupt_bit);
        self.redistributor.write32(gicr_isenabler0, interrupt_bit);
        cpu.dataSynchronizationBarrier();
    }

    fn establishOpaque(
        context: *anyopaque,
        route: interrupt.Route,
        function: *const fn (*anyopaque) void,
        handler_context: *anyopaque,
    ) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        if (route.line < first_ppi_intid or route.line > last_ppi_intid) {
            return error.UnsupportedInterruptLine;
        }

        try self.handlers.establish(route.line, function, handler_context);
        errdefer self.handlers.remove(route.line);
        try self.configurePpi(route, default_priority);
    }

    fn dispatchOpaque(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));
        const token = acknowledgeGroup1();
        const line: u32 = @truncate(token & intid_mask);

        // GICv3 reserves 1020-1023 as special INTIDs; they do not receive EOI.
        if (line >= 1020 and line <= 1023) return;

        defer endOfInterruptGroup1(token);
        if (self.handlers.find(line)) |entry| entry.invoke();
    }
};

test "GIC handler ownership rejects duplicates and supports rollback" {
    const Context = struct {
        invocations: usize = 0,

        fn handle(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.invocations += 1;
        }
    };

    var context: Context = .{};
    var table: HandlerTable = .{};
    try table.establish(30, Context.handle, &context);
    try std.testing.expectError(
        error.InterruptAlreadyEstablished,
        table.establish(30, Context.handle, &context),
    );
    table.find(30).?.invoke();
    try std.testing.expectEqual(@as(usize, 1), context.invocations);

    table.remove(30);
    try std.testing.expect(table.find(30) == null);
    try table.establish(30, Context.handle, &context);
}

fn validateConfig(config: Config) !void {
    if (config.distributor.size() < minimum_distributor_size) {
        return error.DistributorRegionTooSmall;
    }
    if (config.redistributor_stride < minimum_redistributor_size or
        config.redistributor_stride % 0x1_0000 != 0)
    {
        return error.InvalidRedistributorStride;
    }
    if (config.redistributors.size() < config.redistributor_stride) {
        return error.RedistributorRegionTooSmall;
    }
}

fn prepareDistributor(distributor: MmioRegion) !void {
    var control = distributor.read32(gicd_ctlr);

    // Disable both possible Group-enable aliases before changing ARE. Moving
    // from legacy routing to affinity routing while a group is enabled is
    // architecturally UNPREDICTABLE.
    if ((control & gicd_ctlr_group_enable_mask) != 0) {
        distributor.write32(gicd_ctlr, control & ~gicd_ctlr_group_enable_mask);
        try waitDistributorRwp(distributor);
        control = distributor.read32(gicd_ctlr);
    }

    if ((control & gicd_ctlr_are) == 0) {
        distributor.write32(gicd_ctlr, control | gicd_ctlr_are);
        try waitDistributorRwp(distributor);
        if ((distributor.read32(gicd_ctlr) & gicd_ctlr_are) == 0) {
            return error.AffinityRoutingUnavailable;
        }
    }
}

fn enableDistributorGroup1(distributor: MmioRegion) !void {
    const control = distributor.read32(gicd_ctlr);
    distributor.write32(gicd_ctlr, control | gicd_ctlr_enable_group1);
    cpu.dataSynchronizationBarrier();
    if ((distributor.read32(gicd_ctlr) & gicd_ctlr_enable_group1) == 0) {
        return error.Group1EnableFailed;
    }
}

fn findRedistributor(config: Config) !MmioRegion {
    const target_affinity = currentRedistributorAffinity();
    var offset: usize = 0;

    while (offset <= config.redistributors.size() - config.redistributor_stride) : (offset += config.redistributor_stride) {
        const frame = try config.redistributors.subregion(offset, config.redistributor_stride);
        const typer = frame.read64(gicr_typer);
        const affinity: u32 = @truncate(typer >> 32);
        if (affinity == target_affinity) return frame;
        if ((typer & gicr_typer_last) != 0) break;
    }

    return error.RedistributorNotFound;
}

fn wakeRedistributor(redistributor: MmioRegion) !void {
    const waker = redistributor.read32(gicr_waker);
    redistributor.write32(gicr_waker, waker & ~gicr_waker_processor_sleep);

    for (0..maximum_poll_iterations) |_| {
        if ((redistributor.read32(gicr_waker) & gicr_waker_children_asleep) == 0) return;
        std.atomic.spinLoopHint();
    }
    return error.RedistributorWakeTimeout;
}

fn initializeCpuInterface() !void {
    var sre = readSystemRegisterEnable();
    sre |= icc_sre_sre;
    writeSystemRegisterEnable(sre);
    cpu.instructionSynchronizationBarrier();
    if ((readSystemRegisterEnable() & icc_sre_sre) == 0) {
        return error.SystemRegisterInterfaceUnavailable;
    }

    writePriorityMask(0xff);
    writeBinaryPointGroup1(0);

    var control = readControl();
    control &= ~icc_ctlr_eoi_mode;
    writeControl(control);
    cpu.instructionSynchronizationBarrier();
    if ((readControl() & icc_ctlr_eoi_mode) != 0) {
        return error.UnsupportedEoiMode;
    }

    writeGroup1Enable(1);
    cpu.instructionSynchronizationBarrier();
}

fn waitDistributorRwp(distributor: MmioRegion) !void {
    for (0..maximum_poll_iterations) |_| {
        if ((distributor.read32(gicd_ctlr) & gicd_ctlr_rwp) == 0) return;
        std.atomic.spinLoopHint();
    }
    return error.DistributorWriteTimeout;
}

fn waitRedistributorRwp(redistributor: MmioRegion) !void {
    for (0..maximum_poll_iterations) |_| {
        if ((redistributor.read32(gicr_ctlr) & gicr_ctlr_rwp) == 0) return;
        std.atomic.spinLoopHint();
    }
    return error.RedistributorWriteTimeout;
}

/// Return Aff3:Aff2:Aff1:Aff0 in GIC redistributor affinity format.
inline fn currentRedistributorAffinity() u32 {
    const mpidr = asm volatile ("mrs %[value], MPIDR_EL1"
        : [value] "=r" (-> u64),
    );
    const aff0_to_aff2: u32 = @truncate(mpidr & 0x00ff_ffff);
    const aff3: u32 = @truncate((mpidr >> 32) & 0xff);
    return aff0_to_aff2 | (aff3 << 24);
}

inline fn acknowledgeGroup1() u64 {
    return asm volatile ("mrs %[token], ICC_IAR1_EL1"
        : [token] "=r" (-> u64),
        :
        : .{ .memory = true });
}

inline fn endOfInterruptGroup1(token: u64) void {
    asm volatile ("msr ICC_EOIR1_EL1, %[token]"
        :
        : [token] "r" (token),
        : .{ .memory = true });
}

inline fn readSystemRegisterEnable() u64 {
    return asm volatile ("mrs %[value], ICC_SRE_EL1"
        : [value] "=r" (-> u64),
    );
}

inline fn writeSystemRegisterEnable(value: u64) void {
    asm volatile ("msr ICC_SRE_EL1, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

inline fn readControl() u64 {
    return asm volatile ("mrs %[value], ICC_CTLR_EL1"
        : [value] "=r" (-> u64),
    );
}

inline fn writeControl(value: u64) void {
    asm volatile ("msr ICC_CTLR_EL1, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

inline fn writePriorityMask(value: u64) void {
    asm volatile ("msr ICC_PMR_EL1, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

inline fn writeBinaryPointGroup1(value: u64) void {
    asm volatile ("msr ICC_BPR1_EL1, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

inline fn writeGroup1Enable(value: u64) void {
    asm volatile ("msr ICC_IGRPEN1_EL1, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}
