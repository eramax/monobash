const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "setuidgid", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: setuidgid USER PROG ARGS\n", .{});

    const alloc = std.heap.page_allocator;
    const user = args[1];
    const cmd = args[2..];

    const user_z = alloc.dupeZ(u8, user) catch return 1;
    const pw = core.c.getpwnam(user_z.ptr);
    if (pw == null) return core.die(1, "setuidgid: unknown user '{s}'\n", .{user});

    _ = core.c.initgroups(user_z.ptr, pw.*.pw_gid);
    _ = core.c.setgid(pw.*.pw_gid);
    _ = core.c.setuid(pw.*.pw_uid);

    const c_argv = alloc.alloc([*c]u8, cmd.len + 1) catch return 126;
    for (cmd, 0..) |arg, j| {
        c_argv[j] = (alloc.dupeZ(u8, arg) catch return 126).ptr;
    }
    c_argv[cmd.len] = null;
    _ = core.c.execvp(c_argv[0], c_argv.ptr);
    return core.die(127, "setuidgid: cannot execute '{s}'\n", .{cmd[0]});
}
