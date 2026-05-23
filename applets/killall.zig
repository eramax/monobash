const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "killall", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var i: usize = 1;
    var sig: c_int = core.c.SIGTERM;
    var quiet = false;

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
        if (std.mem.eql(u8, args[i], "-q")) {
            quiet = true;
            i += 1;
        } else if (args[i].len > 1) {
            const sig_str = args[i][1..];
            sig = signalByName(sig_str) orelse return core.die(1, "killall: unknown signal '{s}'\n", .{sig_str});
            i += 1;
        }
    }

    if (i >= args.len) return core.die(1, "usage: killall [-l] [-q] [-SIG] PROCESS_NAME...\n", .{});

    const my_pid = core.c.getpid();
    var errors: u8 = 0;

    while (i < args.len) : (i += 1) {
        const name = args[i];
        var found = false;

        const d = core.c.opendir("/proc") orelse return 1;
        defer _ = core.c.closedir(d);

        while (true) {
            const entry = core.c.readdir(d) orelse break;
            const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
            const dent_name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
            const pid = std.fmt.parseInt(usize, dent_name, 10) catch continue;
            if (pid == @as(usize, @intCast(my_pid))) continue;

            var path_buf: [128]u8 = undefined;
            const comm_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid}) catch continue;
            var z_buf: [256:0]u8 = undefined;
            if (comm_path.len >= z_buf.len) continue;
            @memcpy(z_buf[0..comm_path.len], comm_path);
            z_buf[comm_path.len] = 0;
            const fd = core.c.open(z_buf[0..comm_path.len :0].ptr, core.c.O_RDONLY);
            if (fd < 0) continue;
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 256) catch continue;
            defer alloc.free(data);
            const comm = std.mem.trim(u8, data, " \t\r\n");

            if (!std.mem.eql(u8, comm, name)) continue;
            found = true;
            if (core.c.kill(@intCast(pid), sig) < 0) {
                errors += 1;
                if (!quiet) core.eprint("killall: can't kill pid {d}\n", .{pid});
            }
        }

        if (!found and !quiet) {
            core.eprint("{s}: no process killed\n", .{name});
            errors += 1;
        }
    }

    return if (errors > 0) 1 else 0;
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
