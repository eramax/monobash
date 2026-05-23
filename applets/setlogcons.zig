const std = @import("std");
const core = @import("core.zig");
const TIOCLINUX: u32 = 0x541C;
const TIOCL_SETKMSGREDIRECT: u8 = 11;
pub const meta = core.AppletMeta{ .name = "setlogcons", .main = main };
pub fn main(args: [][]const u8) u8 {
    var num: u32 = 0;
    if (args.len >= 2) {
        num = std.fmt.parseInt(u32, args[1], 10) catch return core.die(1, "setlogcons: invalid number\n", .{});
        if (num > 63) return core.die(1, "setlogcons: number must be 0-63\n", .{});
    }
    var arg = [2]u8{ TIOCL_SETKMSGREDIRECT, @intCast(num) };
    var tty_buf: [32:0]u8 = undefined;
    const tty_name = std.fmt.bufPrint(&tty_buf, "/dev/tty{d}", .{if (num > 0) num else 1}) catch "/dev/tty1";
    tty_buf[tty_name.len] = 0;
    const fd = core.c.open(@as([*:0]u8, @ptrCast(&tty_buf)), core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "setlogcons: cannot open /dev/tty{d}\n", .{if (num > 0) num else 1});
    defer _ = core.c.close(fd);
    if (core.c.ioctl(fd, TIOCLINUX, &arg) < 0)
        return core.die(1, "setlogcons: TIOCLINUX failed\n", .{});
    return 0;
}
