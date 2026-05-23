const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "hostname", .main = main };

pub fn main(_: [][]const u8) u8 {
    var buf: [256]u8 = undefined;
    if (core.c.gethostname(&buf, buf.len) != 0) return 1;
    const len = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
    core.writeAll(1, buf[0..len]);
    core.writeAll(1, "\n");
    return 0;
}
