const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "hostid", .main = main };

pub fn main(_: [][]const u8) u8 {
    const id = core.c.gethostid();
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{x}\n", .{id}) catch return 1;
    core.writeAll(1, s);
    return 0;
}
