const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "date", .main = main };
pub fn main(_: [][]const u8) u8 {
    var t: c_long = 0;
    _ = core.c.time(&t);
    const tm = core.c.localtime(&t) orelse return 1;
    var buf: [256]u8 = undefined;
    const len = core.c.strftime(&buf, buf.len, "%a %b %e %H:%M:%S %Z %Y", tm);
    if (len == 0) return 1;
    core.writeAll(1, buf[0..len]);
    core.writeAll(1, "\n");
    return 0;
}
