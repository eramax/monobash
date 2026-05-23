const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "pkill", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var i: usize = 1;
    var sig: c_int = core.c.SIGTERM;
    var opt_echo = false;
    var opt_full = false;
    var opt_anchor = false;
    var opt_invert = false;
    var opt_oldest = false;
    var opt_newest = false;
    var opt_sid: ?c_int = null;
    var opt_ppid: ?c_int = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
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
        if (std.mem.eql(u8, args[i], "-e")) { opt_echo = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-f")) { opt_full = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-x")) { opt_anchor = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-v")) { opt_invert = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-o")) { opt_oldest = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-n")) { opt_newest = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-s")) {
            i += 1;
            if (i >= args.len) return core.die(1, "pkill: -s requires SID\n", .{});
            opt_sid = std.fmt.parseInt(c_int, args[i], 10) catch return core.die(1, "pkill: invalid SID\n", .{});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-P")) {
            i += 1;
            if (i >= args.len) return core.die(1, "pkill: -P requires PPID\n", .{});
            opt_ppid = std.fmt.parseInt(c_int, args[i], 10) catch return core.die(1, "pkill: invalid PPID\n", .{});
            i += 1;
            continue;
        }
        if (args[i].len > 1 and args[i][0] == '-') {
            const sig_str = args[i][1..];
            sig = signalByName(sig_str) orelse return core.die(1, "pkill: unknown signal '{s}'\n", .{sig_str});
            i += 1;
            continue;
        }
        return core.die(1, "pkill: unknown option '{s}'\n", .{args[i]});
    }

    if (i >= args.len) return core.die(1, "pkill: no pattern specified\n", .{});
    const pattern = args[i];

    var first_pid: ?c_int = null;
    var last_pid: ?c_int = null;
    var pid_list: std.ArrayListAligned(c_int, null) = .empty;

    const d = core.c.opendir("/proc") orelse return 1;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const dent_name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
        const pid = std.fmt.parseInt(c_int, dent_name, 10) catch continue;

        if (opt_ppid) |ppid| {
            if (!hasParent(pid, ppid)) continue;
        }
        if (opt_sid) |sid| {
            if (!hasSession(pid, sid)) continue;
        }

        const cmd = if (opt_full) getCmdline(pid) orelse continue else getComm(pid) orelse continue;
        if (cmd.len == 0) continue;

        const matched = if (opt_anchor) std.mem.eql(u8, cmd, pattern) else std.mem.indexOf(u8, cmd, pattern) != null;
        if (opt_invert and matched) continue;
        if (!opt_invert and !matched) continue;

        if (opt_oldest) {
            if (first_pid == null or pid < first_pid.?) first_pid = pid;
        } else if (opt_newest) {
            if (last_pid == null or pid > last_pid.?) last_pid = pid;
        } else {
            pid_list.append(alloc, pid) catch {};
        }
    }

    if (opt_oldest) {
        if (first_pid) |pid| {
            _ = core.c.kill(pid, sig);
            if (opt_echo) core.eprint("killed (pid {d})\n", .{pid});
            return 0;
        }
        return 1;
    }
    if (opt_newest) {
        if (last_pid) |pid| {
            _ = core.c.kill(pid, sig);
            if (opt_echo) core.eprint("killed (pid {d})\n", .{pid});
            return 0;
        }
        return 1;
    }

    if (pid_list.items.len == 0) return 1;
    for (pid_list.items) |pid| {
        _ = core.c.kill(pid, sig);
        if (opt_echo) core.eprint("killed (pid {d})\n", .{pid});
    }
    return 0;
}

fn getComm(pid: c_int) ?[]const u8 {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid}) catch return null;
    var z_buf: [256:0]u8 = undefined;
    if (path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(z_buf[0..path.len :0].ptr, core.c.O_RDONLY); if (fd < 0) return null;
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 4096) catch return null;
    defer std.heap.page_allocator.free(data);
    return std.mem.trim(u8, data, " \t\r\n");
}

fn getCmdline(pid: c_int) ?[]const u8 {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/cmdline", .{pid}) catch return null;
    var z_buf: [256:0]u8 = undefined;
    if (path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(z_buf[0..path.len :0].ptr, core.c.O_RDONLY); if (fd < 0) return null;
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 4096) catch return null;
    defer std.heap.page_allocator.free(data);
    if (data.len == 0) return null;
    var result = std.heap.page_allocator.alloc(u8, data.len) catch return null;
    for (data, 0..) |ch, j| result[j] = if (ch == 0) ' ' else ch;
    return std.mem.trim(u8, result, " \t\r\n");
}

fn hasParent(pid: c_int, ppid: c_int) bool {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch return false;
    var z_buf: [256:0]u8 = undefined;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(z_buf[0..path.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 4096) catch return false;
    defer std.heap.page_allocator.free(data);
    const close_paren = std.mem.lastIndexOfScalar(u8, data, ')') orelse return false;
    const rest = data[close_paren + 2 ..];
    var fields = std.mem.tokenizeScalar(u8, rest, ' ');
    _ = fields.next() orelse return false;
    const ppid_str = fields.next() orelse return false;
    const found = std.fmt.parseInt(c_int, ppid_str, 10) catch return false;
    return found == ppid;
}

fn hasSession(pid: c_int, sid: c_int) bool {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch return false;
    var z_buf: [256:0]u8 = undefined;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(z_buf[0..path.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 4096) catch return false;
    defer std.heap.page_allocator.free(data);
    const close_paren = std.mem.lastIndexOfScalar(u8, data, ')') orelse return false;
    const rest = data[close_paren + 2 ..];
    var fields = std.mem.tokenizeScalar(u8, rest, ' ');
    _ = fields.next() orelse return false;
    _ = fields.next() orelse return false;
    _ = fields.next() orelse return false;
    const sid_str = fields.next() orelse return false;
    const found = std.fmt.parseInt(c_int, sid_str, 10) catch return false;
    return found == sid;
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
