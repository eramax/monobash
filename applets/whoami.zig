const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "whoami", .main = main };

pub fn main(_: [][]const u8) u8 {
    const pw = core.c.getpwuid(core.c.getuid());
    if (pw == null) return 1;
    const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0);
    _ = core.c.write(1, name.ptr, name.len);
    _ = core.c.write(1, "\n", 1);
    return 0;
}
