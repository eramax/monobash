const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "envuidgid", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: envuidgid USER PROG ARGS\n", .{});

    const alloc = std.heap.page_allocator;
    const user = args[1];
    const cmd = args[2..];

    const user_z = alloc.dupeZ(u8, user) catch return 1;
    const pw = core.c.getpwnam(user_z.ptr);
    if (pw == null) return core.die(1, "envuidgid: unknown user '{s}'\n", .{user});

    const uid_str = std.fmt.allocPrint(alloc, "{d}", .{pw.*.pw_uid}) catch return 1;
    const gid_str = std.fmt.allocPrint(alloc, "{d}", .{pw.*.pw_gid}) catch return 1;

    const uid_z = alloc.dupeZ(u8, uid_str) catch return 1;
    const gid_z = alloc.dupeZ(u8, gid_str) catch return 1;
    _ = core.c.setenv("UID", uid_z.ptr, 1);
    _ = core.c.setenv("GID", gid_z.ptr, 1);

    const c_argv = alloc.alloc([*c]u8, cmd.len + 1) catch return 126;
    for (cmd, 0..) |arg, j| {
        c_argv[j] = (alloc.dupeZ(u8, arg) catch return 126).ptr;
    }
    c_argv[cmd.len] = null;
    _ = core.c.execvp(c_argv[0], c_argv.ptr);
    return core.die(127, "envuidgid: cannot execute '{s}'\n", .{cmd[0]});
}
