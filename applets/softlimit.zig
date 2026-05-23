const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "softlimit", .main = main };

fn parseSize(s: []const u8) !u64 {
    if (s.len == 0) return error.Invalid;
    const suffix = s[s.len - 1];
    const num = if (suffix == 'k' or suffix == 'm' or suffix == 'g' or suffix == 'b')
        s[0 .. s.len - 1]
    else
        s;
    if (num.len == 0) return error.Invalid;
    var val = try std.fmt.parseUnsigned(u64, num, 10);
    switch (suffix) {
        'k' => val *= 1024,
        'm' => val *= 1024 * 1024,
        'g' => val *= 1024 * 1024 * 1024,
        else => {},
    }
    return val;
}

fn setLimit(res: c_int, val: u64) void {
    var lim: core.c.struct_rlimit = undefined;
    lim.rlim_cur = @intCast(val);
    lim.rlim_max = @intCast(val);
    _ = core.c.setrlimit(@as(c_uint, @intCast(res)), &lim);
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: softlimit [OPTIONS] PROG ARGS\n", .{});

    var i: usize = 1;
    var opt_a: ?u64 = null;
    var opt_c: ?u64 = null;
    var opt_d: ?u64 = null;
    var opt_f: ?u64 = null;
    var opt_l: ?u64 = null;
    var opt_o: ?u64 = null;
    var opt_p: ?u64 = null;
    var opt_r: ?u64 = null;
    var opt_s: ?u64 = null;
    var opt_t: ?u64 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) { i += 1; break; }
        switch (args[i][1]) {
            'a' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -a requires arg\n", .{});
                opt_a = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -a\n", .{}); },
            'c' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -c requires arg\n", .{});
                opt_c = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -c\n", .{}); },
            'd' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -d requires arg\n", .{});
                opt_d = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -d\n", .{}); },
            'f' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -f requires arg\n", .{});
                opt_f = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -f\n", .{}); },
            'l' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -l requires arg\n", .{});
                opt_l = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -l\n", .{}); },
            'm' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -m requires arg\n", .{});
                const v = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -m\n", .{});
                opt_d = v; opt_s = v; opt_l = v; opt_a = v; },
            'o' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -o requires arg\n", .{});
                opt_o = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -o\n", .{}); },
            'p' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -p requires arg\n", .{});
                opt_p = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -p\n", .{}); },
            'r' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -r requires arg\n", .{});
                opt_r = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -r\n", .{}); },
            's' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -s requires arg\n", .{});
                opt_s = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -s\n", .{}); },
            't' => { i += 1; if (i >= args.len) return core.die(1, "softlimit: -t requires arg\n", .{});
                opt_t = parseSize(args[i]) catch return core.die(1, "softlimit: invalid -t\n", .{}); },
            else => return core.die(1, "softlimit: unknown option -{c}\n", .{args[i][1]}),
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "softlimit: no command\n", .{});

    const alloc = std.heap.page_allocator;
    const cmd = args[i..];

    const pid = core.c.fork();
    if (pid < 0) return 126;

    if (pid == 0) {
        if (opt_a) |v| { setLimit(core.c.RLIMIT_AS, v); }
        if (opt_c) |v| { setLimit(core.c.RLIMIT_CORE, v); }
        if (opt_d) |v| { setLimit(core.c.RLIMIT_DATA, v); }
        if (opt_f) |v| { setLimit(core.c.RLIMIT_FSIZE, v); }
        if (opt_l) |v| { setLimit(core.c.RLIMIT_MEMLOCK, v); }
        if (opt_o) |v| { setLimit(core.c.RLIMIT_NOFILE, v); }
        if (opt_p) |v| { setLimit(core.c.RLIMIT_NPROC, v); }
        if (opt_r) |v| { setLimit(core.c.RLIMIT_RSS, v); }
        if (opt_s) |v| { setLimit(core.c.RLIMIT_STACK, v); }
        if (opt_t) |v| { setLimit(core.c.RLIMIT_CPU, v); }

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
