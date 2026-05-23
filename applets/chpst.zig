const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "chpst", .main = main };

fn parseSizeValue(s: []const u8) !u64 {
    if (s.len == 0) return error.Invalid;
    const suffix = s[s.len - 1];
    const num_part = if (suffix == 'k' or suffix == 'm' or suffix == 'g')
        s[0 .. s.len - 1]
    else
        s;
    if (num_part.len == 0) return error.Invalid;
    var val = try std.fmt.parseUnsigned(u64, num_part, 10);
    switch (suffix) {
        'k' => val *= 1024,
        'm' => val *= 1024 * 1024,
        'g' => val *= 1024 * 1024 * 1024,
        else => {},
    }
    return val;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: chpst [-u USER[:GROUP]] [-m N] [-d N] [-o N] [-p N] CMD...\n", .{});

    var i: usize = 1;
    var opt_user: ?[]const u8 = null;
    var opt_group: ?[]const u8 = null;
    var opt_mem: ?u64 = null;
    var opt_data: ?u64 = null;
    var opt_nofile: ?u64 = null;
    var opt_nproc: ?u64 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) {
            i += 1;
            break;
        }
        switch (args[i][1]) {
            'u' => {
                i += 1;
                if (i >= args.len) return core.die(1, "chpst: -u requires argument\n", .{});
                const val = args[i];
                if (std.mem.indexOfScalar(u8, val, ':')) |colon| {
                    opt_user = val[0..colon];
                    opt_group = val[colon + 1 ..];
                } else {
                    opt_user = val;
                }
            },
            'm' => {
                i += 1;
                if (i >= args.len) return core.die(1, "chpst: -m requires argument\n", .{});
                opt_mem = parseSizeValue(args[i]) catch return core.die(1, "chpst: invalid -m value '{s}'\n", .{args[i]});
            },
            'd' => {
                i += 1;
                if (i >= args.len) return core.die(1, "chpst: -d requires argument\n", .{});
                opt_data = parseSizeValue(args[i]) catch return core.die(1, "chpst: invalid -d value '{s}'\n", .{args[i]});
            },
            'o' => {
                i += 1;
                if (i >= args.len) return core.die(1, "chpst: -o requires argument\n", .{});
                opt_nofile = parseSizeValue(args[i]) catch return core.die(1, "chpst: invalid -o value '{s}'\n", .{args[i]});
            },
            'p' => {
                i += 1;
                if (i >= args.len) return core.die(1, "chpst: -p requires argument\n", .{});
                opt_nproc = parseSizeValue(args[i]) catch return core.die(1, "chpst: invalid -p value '{s}'\n", .{args[i]});
            },
            else => return core.die(1, "chpst: unknown option -{c}\n", .{args[i][1]}),
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "chpst: no command specified\n", .{});
    const cmd = args[i..];

    const alloc = std.heap.page_allocator;

    const pid = core.c.fork();
    if (pid < 0) return 126;

    if (pid == 0) {
        if (opt_mem) |v| {
            var lim: core.c.struct_rlimit = undefined;
            lim.rlim_cur = @intCast(v);
            lim.rlim_max = @intCast(v);
            _ = core.c.setrlimit(core.c.RLIMIT_AS, &lim);
        }
        if (opt_data) |v| {
            var lim: core.c.struct_rlimit = undefined;
            lim.rlim_cur = @intCast(v);
            lim.rlim_max = @intCast(v);
            _ = core.c.setrlimit(core.c.RLIMIT_DATA, &lim);
        }
        if (opt_nofile) |v| {
            var lim: core.c.struct_rlimit = undefined;
            lim.rlim_cur = @intCast(v);
            lim.rlim_max = @intCast(v);
            _ = core.c.setrlimit(core.c.RLIMIT_NOFILE, &lim);
        }
        if (opt_nproc) |v| {
            var lim: core.c.struct_rlimit = undefined;
            lim.rlim_cur = @intCast(v);
            lim.rlim_max = @intCast(v);
            _ = core.c.setrlimit(core.c.RLIMIT_NPROC, &lim);
        }

        if (opt_user) |user| {
            const user_z = alloc.dupeZ(u8, user) catch core.c._exit(111);
            const pw = core.c.getpwnam(user_z.ptr);
            if (pw == null) core.c._exit(111);
            const uid = pw.*.pw_uid;
            const gid = if (opt_group) |grp| blk: {
                const grp_z = alloc.dupeZ(u8, grp) catch core.c._exit(111);
                const gr = core.c.getgrnam(grp_z.ptr);
                if (gr == null) core.c._exit(111);
                break :blk gr.*.gr_gid;
            } else pw.*.pw_gid;

            _ = core.c.initgroups(user_z.ptr, gid);
            _ = core.c.setgid(gid);
            _ = core.c.setuid(uid);
        }

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
