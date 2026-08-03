//! Arm generic non-secure physical timer (CNTP) support for the active core.

const std = @import("std");
const cpu = @import("../cpu.zig");
const system_timer = @import("../../../timer.zig");

const control_enable: u64 = 1 << 0;

pub const Timer = struct {
    frequency_hz: u64,
    period_ticks: u64 = 0,
    next_deadline: u64 = 0,

    pub fn init() !Timer {
        const frequency_hz = readFrequency();
        if (frequency_hz == 0) return error.InvalidCounterFrequency;

        disable();
        return .{ .frequency_hz = frequency_hz };
    }

    pub fn device(self: *Timer) system_timer.Device {
        return .{
            .context = self,
            .arm_function = armOpaque,
            .rearm_function = rearmOpaque,
        };
    }

    fn arm(self: *Timer, ticks_per_second: u64) !void {
        if (ticks_per_second == 0) return error.InvalidTickRate;

        const period_ticks = self.frequency_hz / ticks_per_second;
        if (period_ticks == 0) return error.TickRateTooHigh;
        self.period_ticks = period_ticks;

        self.next_deadline = std.math.add(u64, readCounter(), self.period_ticks) catch
            std.math.maxInt(u64);
        writeCompareValue(self.next_deadline);
        writeControl(control_enable);
        cpu.instructionSynchronizationBarrier();
    }

    /// Move the level-sensitive timer source back into the future. This must
    /// happen before the GIC end-of-interrupt write.
    fn rearm(self: *Timer) void {
        const now = readCounter();
        var next = std.math.add(u64, self.next_deadline, self.period_ticks) catch
            std.math.maxInt(u64);
        if (next <= now) {
            next = std.math.add(u64, now, self.period_ticks) catch std.math.maxInt(u64);
        }
        self.next_deadline = next;
        writeCompareValue(next);
        cpu.instructionSynchronizationBarrier();
    }

    fn armOpaque(context: *anyopaque, ticks_per_second: u64) !void {
        const self: *Timer = @ptrCast(@alignCast(context));
        try self.arm(ticks_per_second);
    }

    fn rearmOpaque(context: *anyopaque) void {
        const self: *Timer = @ptrCast(@alignCast(context));
        self.rearm();
    }
};

fn disable() void {
    writeControl(0);
    cpu.instructionSynchronizationBarrier();
}

inline fn readFrequency() u64 {
    return asm volatile ("mrs %[value], CNTFRQ_EL0"
        : [value] "=r" (-> u64),
    );
}

inline fn readCounter() u64 {
    return asm volatile ("mrs %[value], CNTPCT_EL0"
        : [value] "=r" (-> u64),
    );
}

inline fn writeCompareValue(value: u64) void {
    asm volatile ("msr CNTP_CVAL_EL0, %[value]"
        :
        : [value] "r" (value),
    );
}

inline fn writeControl(value: u64) void {
    asm volatile ("msr CNTP_CTL_EL0, %[value]"
        :
        : [value] "r" (value),
    );
}
