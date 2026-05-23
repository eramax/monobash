const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sync", .main = main };

pub fn main(_: [][]const u8) u8 {
    core.c.sync();
    return 0;
}
