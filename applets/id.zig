const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "id", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const uid = core.c.getuid();
    const gid = core.c.getgid();
    const pw = core.c.getpwuid(uid);
    const gr = core.c.getgrgid(gid);
    const user = if (pw != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0) else "?";
    const group = if (gr != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(gr.*.gr_name)), 0) else "?";
    const out = std.fmt.allocPrint(std.heap.page_allocator, "uid={d}({s}) gid={d}({s})\n", .{ uid, user, gid, group }) catch return 1;
    defer std.heap.page_allocator.free(out);
    core.writeAll(1, out);
    return 0;
}
