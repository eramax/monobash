const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "false", .main = main };
pub fn main(_: [][]const u8) u8 { return 1; }
