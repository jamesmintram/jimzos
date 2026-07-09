const gpio = @import("../io/gpio.zig");
const mbox = @import("../io/mbox.zig");
const mmio = @import("../io/mmio.zig");

pub fn prepareEarlyPl011(clock_hz: u32) !void {
    mbox.mbox[0] = 9 * 4;
    mbox.mbox[1] = mbox.MBOX_REQUEST;
    mbox.mbox[2] = mbox.MBOX_TAG_SETCLKRATE;
    mbox.mbox[3] = 12;
    mbox.mbox[4] = 8;
    mbox.mbox[5] = 2;
    mbox.mbox[6] = clock_hz;
    mbox.mbox[7] = 0;
    mbox.mbox[8] = mbox.MBOX_TAG_LAST;
    if (mbox.mboxCall(mbox.MBOX_CH_PROP) == null) return error.ClockSetupFailed;

    var function_select = mmio.read(gpio.GPFSEL1) orelse return error.GpioReadFailed;
    function_select &= ~@as(u32, (7 << 12) | (7 << 15));
    function_select |= (4 << 12) | (4 << 15);
    if (mmio.write(gpio.GPFSEL1, function_select) == null) return error.GpioWriteFailed;

    if (mmio.write(gpio.GPPUD, 0) == null) return error.GpioWriteFailed;
    mmio.wait(150);
    if (mmio.write(gpio.GPPUDCLK0, (1 << 14) | (1 << 15)) == null) return error.GpioWriteFailed;
    mmio.wait(150);
    if (mmio.write(gpio.GPPUDCLK0, 0) == null) return error.GpioWriteFailed;
}
