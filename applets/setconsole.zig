const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "setconsole", .main = main };
pub fn main(args: [][]const u8) u8 {
    var reset: bool = false;
    var device: []const u8 = "/dev/tty";
    var i: usize = 1;
    if (i < args.len and std.mem.eql(u8, args[i], "-r")) {
        reset = true;
        i += 1;
    }
    if (i < args.len) {
        device = args[i];
        i += 1;
    }
    if (i < args.len) return core.die(1, "usage: setconsole [-r] [DEVICE]\n", .{});
    if (reset) device = "/dev/console";
    var buf: [4096:0]u8 = undefined;
    if (device.len >= buf.len) return 1;
    @memcpy(buf[0..device.len], device);
    buf[device.len] = 0;
    const fd = core.c.open(&buf, core.c.O_WRONLY);
    if (fd < 0) return core.die(1, "setconsole: cannot open {s}\n", .{device});
    defer _ = core.c.close(fd);
    if (core.c.ioctl(fd, core.c.TIOCCONS, @as(c_ulong, 0)) < 0)
        return core.die(1, "setconsole: TIOCCONS failed\n", .{});
    return 0;
}
