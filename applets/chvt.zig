const std = @import("std");
const core = @import("core.zig");
const VT_ACTIVATE: u32 = 0x5606;
const VT_WAITACTIVE: u32 = 0x5607;
pub const meta = core.AppletMeta{ .name = "chvt", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: chvt N\n", .{});
    const num = std.fmt.parseInt(u32, args[1], 10) catch return core.die(1, "chvt: invalid number\n", .{});
    if (num < 1 or num > 63) return core.die(1, "chvt: VT number must be 1-63\n", .{});
    const fd = core.c.open("/dev/tty0", core.c.O_RDWR);
    if (fd < 0) return core.die(1, "chvt: cannot open /dev/tty0\n", .{});
    defer _ = core.c.close(fd);
    if (core.c.ioctl(fd, VT_ACTIVATE, num) < 0)
        return core.die(1, "chvt: VT_ACTIVATE failed\n", .{});
    if (core.c.ioctl(fd, VT_WAITACTIVE, num) < 0)
        return core.die(1, "chvt: VT_WAITACTIVE failed\n", .{});
    return 0;
}
