const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "setpriv", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: setpriv [OPTIONS] PROG ARGS\n", .{});

    const alloc = std.heap.page_allocator;
    var i: usize = 1;
    var opt_dump = false;
    var opt_nnp = false;
    var cmd_start: usize = args.len;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            cmd_start = i;
            break;
        }
        if (std.mem.eql(u8, args[i], "--dump") or std.mem.eql(u8, args[i], "-d")) {
            opt_dump = true;
        } else if (std.mem.eql(u8, args[i], "--nnp") or std.mem.eql(u8, args[i], "--no-new-privs")) {
            opt_nnp = true;
        } else if (std.mem.startsWith(u8, args[i], "--inh-caps")) {
            i += 1;
        } else if (std.mem.startsWith(u8, args[i], "--ambient-caps")) {
            i += 1;
        } else {
            cmd_start = i;
            break;
        }
        i += 1;
    }

    if (opt_dump) {
        var ruid: core.c.uid_t = undefined;
        var euid: core.c.uid_t = undefined;
        var suid: core.c.uid_t = undefined;
        var rgid: core.c.gid_t = undefined;
        var egid: core.c.gid_t = undefined;
        var sgid: core.c.gid_t = undefined;
        _ = core.c.getresuid(&ruid, &euid, &suid);
        _ = core.c.getresgid(&rgid, &egid, &sgid);

        core.writeAll(1, std.fmt.allocPrint(alloc, "uid: {d}\neuid: {d}\ngid: {d}\negid: {d}\n", .{ ruid, euid, rgid, egid }) catch return 1);
        return 0;
    }

    if (cmd_start >= args.len or cmd_start < i) cmd_start = i;
    if (cmd_start >= args.len) return core.die(1, "setpriv: no command specified\n", .{});

    if (opt_nnp) {
        _ = core.c.prctl(@as(c_int, 38), @as(c_ulong, 1), @as(c_ulong, 0), @as(c_ulong, 0), @as(c_ulong, 0));
    }

    const cmd = args[cmd_start..];
    const pid = core.c.fork();
    if (pid < 0) return 126;

    if (pid == 0) {
        const c_argv = alloc.alloc([*c]u8, cmd.len + 1) catch core.c._exit(126);
        for (cmd, 0..) |arg, j| {
            c_argv[j] = (alloc.dupeZ(u8, arg) catch core.c._exit(126)).ptr;
        }
        c_argv[cmd.len] = null;
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }

    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 1;
}
