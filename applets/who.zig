const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "who", .main = main };

pub fn main(_: [][]const u8) u8 {
    const login = core.c.getlogin();
    const name = if (login != null) blk: {
        break :blk std.mem.sliceTo(@as([*c]u8, @ptrCast(login)), 0);
    } else blk: {
        const pw = core.c.getpwuid(core.c.getuid());
        if (pw == null) return 1;
        break :blk std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0);
    };
    core.writeAll(1, name);
    core.writeAll(1, "\n");
    return 0;
}
