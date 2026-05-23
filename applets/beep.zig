const std = @import("std");
const core = @import("core.zig");
const KIOCSOUND: u32 = 0x4B2F;
const CLOCK_TICK_RATE = 1193180;
const DEFAULT_FREQ = 4000;
const DEFAULT_LENGTH: u32 = 30;
const DEFAULT_DELAY: u32 = 0;
const DEFAULT_REP: u32 = 1;
pub const meta = core.AppletMeta{ .name = "beep", .main = main };
fn getConsoleFd() ?c_int {
    const paths = [_][:0]const u8{"/dev/console", "/dev/tty0", "/dev/tty"};
    inline for (paths) |p| {
        const fd = core.c.open(p.ptr, core.c.O_RDONLY);
        if (fd >= 0) return fd;
    }
    return null;
}
pub fn main(args: [][]const u8) u8 {
    var freq: c_uint = DEFAULT_FREQ;
    var length = DEFAULT_LENGTH;
    var delay = DEFAULT_DELAY;
    var rep = DEFAULT_REP;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-f") and i + 1 < args.len) {
            i += 1;
            freq = std.fmt.parseInt(u32, args[i], 10) catch return core.die(1, "beep: bad freq\n", .{});
        } else if (std.mem.eql(u8, args[i], "-l") and i + 1 < args.len) {
            i += 1;
            length = std.fmt.parseInt(u32, args[i], 10) catch return core.die(1, "beep: bad length\n", .{});
        } else if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            i += 1;
            delay = std.fmt.parseInt(u32, args[i], 10) catch return core.die(1, "beep: bad delay\n", .{});
        } else if (std.mem.eql(u8, args[i], "-r") and i + 1 < args.len) {
            i += 1;
            rep = std.fmt.parseInt(u32, args[i], 10) catch return core.die(1, "beep: bad reps\n", .{});
        } else {
            return core.die(1, "usage: beep [-f freq] [-l len] [-d delay] [-r reps]\n", .{});
        }
    }
    const fd = getConsoleFd() orelse return core.die(1, "beep: cannot open console\n", .{});
    defer _ = core.c.close(fd);
    var r = rep;
    while (r > 0) : (r -= 1) {
        const tick_div = CLOCK_TICK_RATE / @as(c_uint, freq);
        if (core.c.ioctl(fd, KIOCSOUND, tick_div) < 0)
            return core.die(1, "beep: KIOCSOUND failed\n", .{});
        _ = core.c.usleep(length * 1000);
        _ = core.c.ioctl(fd, KIOCSOUND, @as(c_int, 0));
        if (r > 1 and delay > 0) _ = core.c.usleep(delay * 1000);
    }
    return 0;
}
