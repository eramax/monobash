const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "unlink", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: unlink FILE\n", .{});
    var buf: [4096:0]u8 = undefined;
    if (args[1].len >= buf.len) return 1;
    @memcpy(buf[0..args[1].len], args[1]);
    buf[args[1].len] = 0;
    return if (core.c.unlink(&buf) == 0) 0 else 1;
}
