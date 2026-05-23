const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "kill", .main = main };

const signals = [_]struct { name: []const u8, num: c_int }{
    .{ .name = "HUP", .num = 1 },
    .{ .name = "INT", .num = 2 },
    .{ .name = "QUIT", .num = 3 },
    .{ .name = "ILL", .num = 4 },
    .{ .name = "TRAP", .num = 5 },
    .{ .name = "ABRT", .num = 6 },
    .{ .name = "BUS", .num = 7 },
    .{ .name = "FPE", .num = 8 },
    .{ .name = "KILL", .num = 9 },
    .{ .name = "USR1", .num = 10 },
    .{ .name = "SEGV", .num = 11 },
    .{ .name = "USR2", .num = 12 },
    .{ .name = "PIPE", .num = 13 },
    .{ .name = "ALRM", .num = 14 },
    .{ .name = "TERM", .num = 15 },
    .{ .name = "STKFLT", .num = 16 },
    .{ .name = "CHLD", .num = 17 },
    .{ .name = "CONT", .num = 18 },
    .{ .name = "STOP", .num = 19 },
    .{ .name = "TSTP", .num = 20 },
    .{ .name = "TTIN", .num = 21 },
    .{ .name = "TTOU", .num = 22 },
    .{ .name = "URG", .num = 23 },
    .{ .name = "XCPU", .num = 24 },
    .{ .name = "XFSZ", .num = 25 },
    .{ .name = "VTALRM", .num = 26 },
    .{ .name = "PROF", .num = 27 },
    .{ .name = "WINCH", .num = 28 },
    .{ .name = "IO", .num = 29 },
    .{ .name = "PWR", .num = 30 },
    .{ .name = "SYS", .num = 31 },
};

fn signalByName(name: []const u8) ?c_int {
    const stripped = if (std.mem.startsWith(u8, name, "SIG")) name[3..] else name;
    for (signals) |s| {
        if (std.mem.eql(u8, s.name, stripped)) return s.num;
    }
    const n = std.fmt.parseInt(c_int, name, 10) catch return null;
    return n;
}

fn signalName(num: c_int) ?[]const u8 {
    for (signals) |s| {
        if (s.num == num) return s.name;
    }
    return null;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: kill [-l] [-s SIGNAL|-SIGNAL] PID\n", .{});

    if (std.mem.eql(u8, args[1], "-l")) {
        for (signals, 0..) |s, i| {
            if (i > 0) core.writeAll(1, " ");
            core.writeAll(1, s.name);
        }
        core.writeAll(1, "\n");
        return 0;
    }

    var sig: c_int = core.c.SIGTERM;
    var pid_arg: usize = 1;

    if (args.len > 2 and std.mem.eql(u8, args[1], "-s")) {
        sig = signalByName(args[2]) orelse return core.die(1, "kill: unknown signal '{s}'\n", .{args[2]});
        pid_arg = 3;
    } else if (args[1].len > 1 and args[1][0] == '-') {
        const sig_str = args[1][1..];
        sig = signalByName(sig_str) orelse return core.die(1, "kill: unknown signal '{s}'\n", .{sig_str});
        pid_arg = 2;
    }

    if (pid_arg >= args.len) return core.die(1, "usage: kill [-l] [-s SIGNAL|-SIGNAL] PID\n", .{});
    const pid = std.fmt.parseInt(c_int, args[pid_arg], 10) catch return core.die(1, "kill: invalid PID '{s}'\n", .{args[pid_arg]});

    const rc = core.c.kill(pid, sig);
    if (rc < 0) return core.die(1, "kill: failed\n", .{});

    return 0;
}
