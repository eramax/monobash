const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "users", .main = main };
pub fn main(_: [][]const u8) u8 {
    const login = core.c.getlogin();
    const name = if (login) |n| std.mem.sliceTo(@as([*c]u8, @ptrCast(n)), 0) else blk: {
        const pw = core.c.getpwuid(core.c.getuid());
        break :blk if (pw) |p| std.mem.sliceTo(@as([*c]u8, @ptrCast(p.*.pw_name)), 0) else return 1;
    };
    _ = core.c.write(1, name.ptr, name.len);
    _ = core.c.write(1, "\n", 1);
    return 0;
}
