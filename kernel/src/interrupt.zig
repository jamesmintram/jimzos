//! Machine-independent interrupt routing, establishment, and root dispatch.

const std = @import("std");

pub const Trigger = enum {
    level_high,
    level_low,
    edge_rising,
    edge_falling,
};

/// A route normalized into the owning interrupt controller's namespace.
pub const Route = struct {
    line: u32,
    trigger: Trigger,
};

/// The provider capability an interrupt controller publishes for consumers.
pub const Controller = struct {
    context: *anyopaque,
    establish_function: *const fn (
        *anyopaque,
        Route,
        *const fn (*anyopaque) void,
        *anyopaque,
    ) anyerror!void,

    fn establish(
        self: Controller,
        route: Route,
        function: *const fn (*anyopaque) void,
        handler_context: *anyopaque,
    ) !void {
        try self.establish_function(
            self.context,
            route,
            function,
            handler_context,
        );
    }
};

/// One controller-specific route, ready for a consumer to establish.
pub const Resource = struct {
    controller: Controller,
    route: Route,

    pub fn establish(
        self: Resource,
        function: *const fn (*anyopaque) void,
        context: *anyopaque,
    ) !void {
        try self.controller.establish(self.route, function, context);
    }
};

/// The separate provider capability that can service the CPU's root IRQ.
/// Ordinary interrupt consumers retain `Resource`, never this capability.
pub const RootController = struct {
    context: *anyopaque,
    dispatch_function: *const fn (*anyopaque) void,

    fn dispatch(self: RootController) void {
        self.dispatch_function(self.context);
    }
};

// The CPU exception entry has one machine-wide destination. FDT interrupt
// providers are registered separately and never participate in this slot.
var root_controller: ?RootController = null;

/// Bind the single root controller selected by machine-dependent attachment.
pub fn bindRootController(controller: RootController) !void {
    if (root_controller != null) {
        return error.RootInterruptControllerAlreadyBound;
    }
    root_controller = controller;
}

/// Dispatch an IRQ from the CPU exception entry to the bound root controller.
pub fn dispatchRoot() void {
    const controller = root_controller orelse
        @panic("IRQ arrived before root interrupt controller binding");
    controller.dispatch();
}

test "interrupt resources retain their controller and handler context" {
    const FakeController = struct {
        established: ?Route = null,
        handler_function: ?*const fn (*anyopaque) void = null,
        handler_context: ?*anyopaque = null,

        fn establish(
            context: *anyopaque,
            route: Route,
            function: *const fn (*anyopaque) void,
            handler_context: *anyopaque,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.established = route;
            self.handler_function = function;
            self.handler_context = handler_context;
        }
    };

    const Counter = struct {
        value: usize = 0,

        fn increment(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.value += 1;
        }
    };

    var fake: FakeController = .{};
    var counter: Counter = .{};
    const controller = Controller{
        .context = &fake,
        .establish_function = FakeController.establish,
    };
    const resource = Resource{
        .controller = controller,
        .route = .{ .line = 30, .trigger = .level_high },
    };
    try resource.establish(Counter.increment, &counter);

    try std.testing.expectEqual(resource.route, fake.established.?);
    fake.handler_function.?(fake.handler_context.?);
    try std.testing.expectEqual(@as(usize, 1), counter.value);
}

test "root IRQ dispatch binds one stable controller" {
    const Context = struct {
        dispatches: usize = 0,

        fn dispatch(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.dispatches += 1;
        }

        fn root(self: *@This()) RootController {
            return .{
                .context = self,
                .dispatch_function = dispatch,
            };
        }
    };

    var first: Context = .{};
    var second: Context = .{};
    try bindRootController(first.root());
    defer root_controller = null;
    try std.testing.expectError(
        error.RootInterruptControllerAlreadyBound,
        bindRootController(second.root()),
    );

    dispatchRoot();
    try std.testing.expectEqual(@as(usize, 1), first.dispatches);
    try std.testing.expectEqual(@as(usize, 0), second.dispatches);
}
