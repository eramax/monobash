const std = @import("std");
const core = @import("core.zig");
const KDSETKEYCODE: u32 = 0x4B4D;
const KbKeycode = extern struct {
    scancode: c_uint,
    keycode: c_uint,
};
pub const meta = core.AppletMeta{ .name = "setkeycodes", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len < 3 or (args.len & 1) == 0) return core.die(1, "usage: setkeycodes {{ SCANCODE KEYCODE }}...\n", .{});
    const fd = core.c.open("/dev/tty0", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "setkeycodes: cannot open /dev/tty0\n", .{});
    defer _ = core.c.close(fd);
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        const sc = std.fmt.parseInt(u32, args[i], 16) catch return core.die(1, "setkeycodes: bad scancode\n", .{});
        const kc = std.fmt.parseInt(u32, args[i+1], 10) catch return core.die(1, "setkeycodes: bad keycode\n", .{});
        var a = KbKeycode{ .scancode = sc, .keycode = kc };
        if (core.c.ioctl(fd, KDSETKEYCODE, &a) < 0)
            return core.die(1, "setkeycodes: KDSETKEYCODE failed\n", .{});
    }
    return 0;
}
