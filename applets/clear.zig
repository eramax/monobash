const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "clear", .main = main };
pub fn main(_: [][]const u8) u8 {
    core.writeAll(1, "\x1B[2J\x1B[H");
    return 0;
}
