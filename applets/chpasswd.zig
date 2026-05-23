const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "chpasswd", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    return core.die(1, "chpasswd: not available (requires root)\n", .{});
}
