const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "logname", .main = main };

pub fn main(_: [][]const u8) u8 {
    const login = core.c.getlogin();
    if (login != null) {
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(login)), 0);
        core.writeAll(1, name);
        core.writeAll(1, "\n");
        return 0;
    }
    const pw = core.c.getpwuid(core.c.getuid());
    if (pw == null) return 1;
    const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0);
    core.writeAll(1, name);
    core.writeAll(1, "\n");
    return 0;
}
