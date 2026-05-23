const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "su", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: su USER\n", .{});
    const user = args[1];

    if (core.c.geteuid() != 0) return core.die(1, "su: permission denied (requires root)\n", .{});

    var zuser: [256:0]u8 = undefined;
    if (user.len >= zuser.len) return 1;
    @memcpy(zuser[0..user.len], user);
    zuser[user.len] = 0;
    const pw = core.c.getpwnam(zuser[0..user.len :0].ptr);
    if (pw == null) return core.die(1, "su: unknown user '{s}'\n", .{user});

    const pid = core.c.fork();
    if (pid < 0) return core.die(1, "su: fork failed\n", .{});

    if (pid == 0) {
        _ = core.c.setgid(pw.*.pw_gid);
        _ = core.c.setuid(pw.*.pw_uid);
        const shell = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_shell)), 0);
        var zshell: [256:0]u8 = undefined;
        if (shell.len >= zshell.len) std.process.exit(1);
        @memcpy(zshell[0..shell.len], shell);
        zshell[shell.len] = 0;
        var args_buf: [2][*c]u8 = .{ zshell[0..shell.len :0].ptr, null };
        _ = core.c.execvp(zshell[0..shell.len :0].ptr, &args_buf);
        _ = core.c.execvp("/bin/sh", &args_buf);
        std.process.exit(127);
    }

    var wstatus: c_int = 0;
    while (core.c.waitpid(pid, &wstatus, 0) < 0) {}
    return 0;
}
