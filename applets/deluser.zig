const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "deluser", .main = main };

pub fn main(_: [][]const u8) u8 {
    return core.die(1, "deluser: not available (requires root)\n", .{});
}
