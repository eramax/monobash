const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "chmod", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    const mode_str = args[1];
    const mode = std.fmt.parseInt(u32, mode_str, 8) catch return 1;
    var buf: [4096:0]u8 = undefined;
    const path = args[2];
    if (path.len >= buf.len) return 1;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return if (core.c.chmod(&buf, @intCast(mode)) == 0) 0 else 1;
}
