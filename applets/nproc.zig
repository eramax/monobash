const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "nproc", .main = main };
pub fn main(_: [][]const u8) u8 {
    const n = core.c.sysconf(core.c._SC_NPROCESSORS_ONLN);
    if (n <= 0) return 1;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}\n", .{@as(u64, @intCast(n))}) catch return 1;
    _ = core.c.write(1, s.ptr, s.len);
    return 0;
}
