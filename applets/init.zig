const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "init", .main = main };

pub fn main(_: [][]const u8) u8 {
    core.writeAll(2, "WARNING: this is not a real init process. Use a proper init system (systemd, openrc, etc.).\n");
    return 0;
}
