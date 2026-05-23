const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "login", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: login USER\n", .{});
    const user = args[1];

    var zuser: [256:0]u8 = undefined;
    if (user.len >= zuser.len) return 1;
    @memcpy(zuser[0..user.len], user);
    zuser[user.len] = 0;
    const pw = core.c.getpwnam(zuser[0..user.len :0].ptr);
    if (pw == null) return core.die(1, "login: unknown user '{s}'\n", .{user});

    return 0;
}
