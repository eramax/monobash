const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "eject", .main = main };

const CDROMEJECT: u64 = 0x5309;
const CDROMCLOSETRAY: u64 = 0x5319;

pub fn main(args: [][]const u8) u8 {
    var device: []const u8 = "/dev/cdrom";
    var cmd = CDROMEJECT;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-t")) {
            cmd = CDROMCLOSETRAY;
        } else if (std.mem.eql(u8, arg, "-T")) {
            cmd = CDROMCLOSETRAY;
        } else if (arg.len > 0 and arg[0] != '-') {
            device = arg;
        } else {
            return core.die(1, "usage: eject [-t|-T] [device]\n", .{});
        }
    }

    // For -T, first try to eject; if that fails, try to close
    if (args.len > 1 and std.mem.eql(u8, args[1], "-T")) {
        var zbuf: [4096:0]u8 = undefined;
        if (device.len >= zbuf.len) return 1;
        @memcpy(zbuf[0..device.len], device);
        zbuf[device.len] = 0;
        const fd = core.c.open(zbuf[0..device.len :0].ptr, core.c.O_RDONLY | core.c.O_NONBLOCK);
        if (fd < 0) return core.die(1, "eject: cannot open {s}\n", .{device});
        defer _ = core.c.close(fd);
        var rc = core.c.ioctl(fd, CDROMEJECT, @as(c_int, 0));
        if (rc < 0) {
            rc = core.c.ioctl(fd, CDROMCLOSETRAY, @as(c_int, 0));
        }
        if (rc < 0) return core.die(1, "eject: ioctl failed\n", .{});
        return 0;
    }

    var zbuf: [4096:0]u8 = undefined;
    if (device.len >= zbuf.len) return 1;
    @memcpy(zbuf[0..device.len], device);
    zbuf[device.len] = 0;
    const fd = core.c.open(zbuf[0..device.len :0].ptr, core.c.O_RDONLY | core.c.O_NONBLOCK);
    if (fd < 0) return core.die(1, "eject: cannot open {s}\n", .{device});
    defer _ = core.c.close(fd);

    if (core.c.ioctl(fd, cmd, @as(c_int, 0)) < 0) {
        return core.die(1, "eject: ioctl failed\n", .{});
    }
    return 0;
}
