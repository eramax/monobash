const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "true", .main = main };
pub fn main(_: [][]const u8) u8 { return 0; }
