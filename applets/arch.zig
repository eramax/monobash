const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "arch", .main = main };
pub fn main(_: [][]const u8) u8 {
    var uts: core.c.struct_utsname = undefined;
    if (core.c.uname(&uts) != 0) return 1;
    const len = std.mem.indexOfScalar(u8, &uts.machine, 0) orelse 65;
    _ = core.c.write(1, @as([*]const u8, @ptrCast(&uts.machine)), len);
    _ = core.c.write(1, "\n", 1);
    return 0;
}
