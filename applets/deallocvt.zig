const std = @import("std");
const core = @import("core.zig");
const VT_DISALLOCATE: u32 = 0x5608;
pub const meta = core.AppletMeta{ .name = "deallocvt", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len > 2) return core.die(1, "usage: deallocvt [N]\n", .{});
    var num: u32 = 0;
    if (args.len >= 2) {
        num = std.fmt.parseInt(u32, args[1], 10) catch return core.die(1, "deallocvt: invalid number\n", .{});
        if (num < 1 or num > 63) return core.die(1, "deallocvt: VT number must be 1-63\n", .{});
    }
    const fd = core.c.open("/dev/console", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "deallocvt: cannot open /dev/console\n", .{});
    defer _ = core.c.close(fd);
    if (core.c.ioctl(fd, VT_DISALLOCATE, num) < 0)
        return core.die(1, "deallocvt: VT_DISALLOCATE failed\n", .{});
    return 0;
}
