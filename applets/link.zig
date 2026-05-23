const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "link", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: link FILE NEWLINK\n", .{});
    var buf1: [4096:0]u8 = undefined;
    var buf2: [4096:0]u8 = undefined;
    if (args[1].len >= buf1.len or args[2].len >= buf2.len) return 1;
    @memcpy(buf1[0..args[1].len], args[1]);
    buf1[args[1].len] = 0;
    @memcpy(buf2[0..args[2].len], args[2]);
    buf2[args[2].len] = 0;
    return if (core.c.link(&buf1, &buf2) == 0) 0 else 1;
}
