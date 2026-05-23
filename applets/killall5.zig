const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "killall5", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var sig: c_int = core.c.SIGTERM;
    var i: usize = 1;
    var omit_pids: std.ArrayListAligned(c_int, null) = .empty;

    if (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-l")) {
            const signals = [_]struct { name: []const u8, num: c_int }{
                .{ .name = "HUP", .num = 1 }, .{ .name = "INT", .num = 2 }, .{ .name = "QUIT", .num = 3 },
                .{ .name = "ILL", .num = 4 }, .{ .name = "TRAP", .num = 5 }, .{ .name = "ABRT", .num = 6 },
                .{ .name = "BUS", .num = 7 }, .{ .name = "FPE", .num = 8 }, .{ .name = "KILL", .num = 9 },
                .{ .name = "USR1", .num = 10 }, .{ .name = "SEGV", .num = 11 }, .{ .name = "USR2", .num = 12 },
                .{ .name = "PIPE", .num = 13 }, .{ .name = "ALRM", .num = 14 }, .{ .name = "TERM", .num = 15 },
                .{ .name = "STKFLT", .num = 16 }, .{ .name = "CHLD", .num = 17 }, .{ .name = "CONT", .num = 18 },
                .{ .name = "STOP", .num = 19 }, .{ .name = "TSTP", .num = 20 }, .{ .name = "TTIN", .num = 21 },
                .{ .name = "TTOU", .num = 22 }, .{ .name = "URG", .num = 23 }, .{ .name = "XCPU", .num = 24 },
                .{ .name = "XFSZ", .num = 25 }, .{ .name = "VTALRM", .num = 26 }, .{ .name = "PROF", .num = 27 },
                .{ .name = "WINCH", .num = 28 }, .{ .name = "IO", .num = 29 }, .{ .name = "PWR", .num = 30 },
                .{ .name = "SYS", .num = 31 },
            };
            for (signals, 0..) |s, j| {
                if (j > 0) core.writeAll(1, " ");
                core.writeAll(1, s.name);
            }
            core.writeAll(1, "\n");
            return 0;
        }
        if (args[i].len > 1 and args[i][1] == 'o') {
            // -o PID will be parsed below
        } else if (args[i].len > 1) {
            const sig_str = args[i][1..];
            sig = signalByName(sig_str) orelse return core.die(1, "killall5: unknown signal '{s}'\n", .{sig_str});
            i += 1;
        }
    }

    while (i < args.len) : (i += 1) {
        if (args[i].len > 2 and args[i][0] == '-' and args[i][1] == 'o') {
            var omit_str = args[i][2..];
            if (omit_str.len == 0) {
                i += 1;
                if (i >= args.len) return core.die(1, "killall5: -o requires PID\n", .{});
                omit_str = args[i];
            }
            const pid = std.fmt.parseInt(c_int, omit_str, 10) catch return core.die(1, "killall5: invalid PID '{s}'\n", .{omit_str});
            omit_pids.append(alloc, pid) catch {};
        } else if (args[i].len > 1 and args[i][0] == '-') {
            const sig_str = args[i][1..];
            sig = signalByName(sig_str) orelse return core.die(1, "killall5: unknown signal '{s}'\n", .{sig_str});
        }
    }

    const my_pid = core.c.getpid();
    const my_sid = core.c.getsid(0);

    // Stop all processes
    if (sig != core.c.SIGSTOP and sig != core.c.SIGCONT) {
        _ = core.c.kill(-1, core.c.SIGSTOP);
    }
    defer {
        if (sig != core.c.SIGSTOP and sig != core.c.SIGCONT) {
            _ = core.c.kill(-1, core.c.SIGCONT);
        }
    }

    var errors: u8 = 2;
    const d = core.c.opendir("/proc") orelse return 1;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const dent_name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
        const pid = std.fmt.parseInt(c_int, dent_name, 10) catch continue;

        if (pid == my_pid or pid == 1) continue;

        // Check session ID
        var stat_buf: [256]u8 = undefined;
        const stat_path = std.fmt.bufPrint(&stat_buf, "/proc/{d}/stat", .{pid}) catch continue;
        var z_buf: [512:0]u8 = undefined;
        if (stat_path.len >= z_buf.len) continue;
        @memcpy(z_buf[0..stat_path.len], stat_path);
        z_buf[stat_path.len] = 0;
        const fd = core.c.open(z_buf[0..stat_path.len :0].ptr, core.c.O_RDONLY);
        if (fd < 0) continue;
        defer _ = core.c.close(fd);
        const data = core.readAll(alloc, fd, 4096) catch continue;
        defer alloc.free(data);

        // Parse: pid (comm) state ppid pgrp session ...
        const close_paren = std.mem.lastIndexOfScalar(u8, data, ')') orelse continue;
        const rest = data[close_paren + 2 ..];
        var fields = std.mem.tokenizeScalar(u8, rest, ' ');
        _ = fields.next() orelse continue; // state
        _ = fields.next() orelse continue; // ppid
        _ = fields.next() orelse continue; // pgrp
        const sid_str = fields.next() orelse continue;
        const sid = std.fmt.parseInt(c_int, sid_str, 10) catch continue;

        if (sid == my_sid or sid == 0) continue;

        // Check omit list
        var should_omit = false;
        for (omit_pids.items) |op| {
            if (pid == op) {
                should_omit = true;
                break;
            }
        }
        if (should_omit) continue;

        _ = core.c.kill(pid, sig);
        errors = 0;
    }

    return errors;
}

fn signalByName(name: []const u8) ?c_int {
    const stripped = if (std.mem.startsWith(u8, name, "SIG")) name[3..] else name;
    const signals = [_]struct { name: []const u8, num: c_int }{
        .{ .name = "HUP", .num = 1 }, .{ .name = "INT", .num = 2 }, .{ .name = "QUIT", .num = 3 },
        .{ .name = "ILL", .num = 4 }, .{ .name = "TRAP", .num = 5 }, .{ .name = "ABRT", .num = 6 },
        .{ .name = "BUS", .num = 7 }, .{ .name = "FPE", .num = 8 }, .{ .name = "KILL", .num = 9 },
        .{ .name = "USR1", .num = 10 }, .{ .name = "SEGV", .num = 11 }, .{ .name = "USR2", .num = 12 },
        .{ .name = "PIPE", .num = 13 }, .{ .name = "ALRM", .num = 14 }, .{ .name = "TERM", .num = 15 },
        .{ .name = "STKFLT", .num = 16 }, .{ .name = "CHLD", .num = 17 }, .{ .name = "CONT", .num = 18 },
        .{ .name = "STOP", .num = 19 }, .{ .name = "TSTP", .num = 20 }, .{ .name = "TTIN", .num = 21 },
        .{ .name = "TTOU", .num = 22 }, .{ .name = "URG", .num = 23 }, .{ .name = "XCPU", .num = 24 },
        .{ .name = "XFSZ", .num = 25 }, .{ .name = "VTALRM", .num = 26 }, .{ .name = "PROF", .num = 27 },
        .{ .name = "WINCH", .num = 28 }, .{ .name = "IO", .num = 29 }, .{ .name = "PWR", .num = 30 },
        .{ .name = "SYS", .num = 31 },
    };
    for (signals) |s| {
        if (std.mem.eql(u8, s.name, stripped)) return s.num;
    }
    const n = std.fmt.parseInt(c_int, name, 10) catch return null;
    return n;
}
