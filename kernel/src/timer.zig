//! Machine-independent system clock built on an attached timer capability.
//!
//! Machine-dependent attachment supplies both the hardware operations and an
//! already-resolved interrupt resource; system-clock policy owns neither the
//! controller nor the firmware binding that produced them.

const std = @import("std");
const interrupt = @import("interrupt.zig");
const kprint = @import("kprint.zig");

pub const default_ticks_per_second: u64 = 1;

/// The narrow capability published by a hardware timer implementation.
pub const Device = struct {
    context: *anyopaque,
    arm_function: *const fn (*anyopaque, u64) anyerror!void,
    rearm_function: *const fn (*anyopaque) void,

    fn arm(self: Device, ticks_per_second: u64) !void {
        try self.arm_function(self.context, ticks_per_second);
    }

    fn rearm(self: Device) void {
        self.rearm_function(self.context);
    }
};

var system_timer: SystemTimer = undefined;
var system_installed = false;

/// Select an attached device for the boot-life system-timer role and establish
/// its interrupt handler. The device remains disabled until `startSystem()`
/// applies the kernel's tick-rate policy.
pub fn installSystem(device: Device, resource: interrupt.Resource) !void {
    if (system_installed) return error.SystemTimerAlreadyInstalled;

    system_timer = SystemTimer.init(device, default_ticks_per_second);
    try system_timer.attach(resource);
    system_installed = true;
}

pub fn startSystem() !void {
    if (!system_installed) return error.SystemTimerNotInstalled;
    try system_timer.start();
}

pub fn isSystemInstalled() bool {
    return system_installed;
}

const SystemTimer = struct {
    device: Device,
    ticks_per_second: u64,
    attached: bool = false,
    tick_count: u64 = 0,
    started: bool = false,

    fn init(device: Device, ticks_per_second: u64) SystemTimer {
        return .{
            .device = device,
            .ticks_per_second = ticks_per_second,
        };
    }

    /// Establish the timer's interrupt handler while leaving CNTP disabled.
    /// `self` must remain at a stable address after this call because it is the
    /// interrupt handler's context.
    fn attach(self: *SystemTimer, resource: interrupt.Resource) !void {
        if (self.attached) return error.AlreadyAttached;

        try resource.establish(handleInterrupt, self);
        self.attached = true;
    }

    /// Arm the periodic clock after boot has attached all interrupt resources.
    fn start(self: *SystemTimer) !void {
        if (!self.attached) return error.NotAttached;
        if (self.started) return error.AlreadyStarted;

        self.tick_count = 0;
        try self.device.arm(self.ticks_per_second);
        self.started = true;
    }

    fn handleInterrupt(raw_context: *anyopaque) void {
        const self: *SystemTimer = @ptrCast(@alignCast(raw_context));

        // Rearm the device before returning to the interrupt controller,
        // which performs its end-of-interrupt operation afterward.
        self.device.rearm();
        self.tick_count +%= 1;
        kprint.write("timer IRQ: count={}\r", .{self.tick_count});
    }
};

test "system timer drives an attached device through its capability" {
    const FakeDevice = struct {
        armed_rate: ?u64 = null,
        rearms: usize = 0,

        fn device(self: *@This()) Device {
            return .{
                .context = self,
                .arm_function = arm,
                .rearm_function = rearm,
            };
        }

        fn arm(context: *anyopaque, ticks_per_second: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.armed_rate = ticks_per_second;
        }

        fn rearm(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.rearms += 1;
        }
    };

    const FakeController = struct {
        handler_function: ?*const fn (*anyopaque) void = null,
        handler_context: ?*anyopaque = null,

        fn establish(
            context: *anyopaque,
            _: interrupt.Route,
            function: *const fn (*anyopaque) void,
            handler_context: *anyopaque,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.handler_function = function;
            self.handler_context = handler_context;
        }
    };

    var device: FakeDevice = .{};
    var controller: FakeController = .{};
    var system = SystemTimer.init(device.device(), 100);
    try system.attach(.{
        .controller = .{
            .context = &controller,
            .establish_function = FakeController.establish,
        },
        .route = .{ .line = 30, .trigger = .level_high },
    });

    try system.start();
    try std.testing.expectEqual(@as(?u64, 100), device.armed_rate);

    controller.handler_function.?(controller.handler_context.?);
    try std.testing.expectEqual(@as(usize, 1), device.rearms);
    try std.testing.expectEqual(@as(u64, 1), system.tick_count);
    try std.testing.expectError(error.AlreadyStarted, system.start());
}
