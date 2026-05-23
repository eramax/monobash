const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "addgroup", .main = main };

pub fn main(_: [][]const u8) u8 {
    return core.die(1, "addgroup: not available (requires root)\n", .{});
}
