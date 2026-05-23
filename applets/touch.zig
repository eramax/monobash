const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "touch", .main = main };

const UTIME_NOW: i64 = 1073741823;
const UTIME_OMIT: i64 = 1073741822;
const ENOENT: c_int = 2;

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var no_create = false;
    var atime = false;
    var mtime = false;
    var ref_file: ?[]const u8 = null;
    var date_str: ?[]const u8 = null;
    // -h (no-dereference) is recognized but not fully implemented
    var no_deref = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        if (std.mem.eql(u8, arg, "-c")) { no_create = true; i += 1; continue; }
        if (std.mem.eql(u8, arg, "-a")) { atime = true; i += 1; continue; }
        if (std.mem.eql(u8, arg, "-m")) { mtime = true; i += 1; continue; }
        if (std.mem.eql(u8, arg, "-h")) { no_deref = true; i += 1; continue; }
        if (std.mem.eql(u8, arg, "-f")) { i += 1; continue; } // ignored, BSD compat
        if (std.mem.eql(u8, arg, "-r")) {
            i += 1; if (i >= args.len) return core.die(1, "touch: missing file argument after -r\n", .{});
            ref_file = args[i]; i += 1; continue;
        }
        if (std.mem.eql(u8, arg, "-t")) {
            i += 1; if (i >= args.len) return core.die(1, "touch: missing date argument after -t\n", .{});
            date_str = args[i]; i += 1; continue;
        }

        for (arg[1..]) |c| {
            switch (c) {
                'c' => no_create = true,
                'a' => atime = true,
                'm' => mtime = true,
                'h' => no_deref = true,
                'f' => {},
                else => return core.die(1, "touch: invalid option -- '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "touch: missing file operand\n", .{});

    var ts: [2]core.c.struct_timespec = undefined;
    ts[0].tv_nsec = UTIME_NOW;
    ts[1].tv_nsec = UTIME_NOW;

    if (ref_file) |rf| {
        var z_rf: [4096:0]u8 = undefined;
        if (rf.len >= z_rf.len) return 1;
        @memcpy(z_rf[0..rf.len], rf);
        z_rf[rf.len] = 0;
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(&z_rf, &st) != 0) {
            core.eprint("touch: cannot stat '{s}': No such file or directory\n", .{rf});
            return 1;
        }
        ts[0].tv_sec = st.st_atim.tv_sec;
        ts[0].tv_nsec = st.st_atim.tv_nsec;
        ts[1].tv_sec = st.st_mtim.tv_sec;
        ts[1].tv_nsec = st.st_mtim.tv_nsec;
    }

    if (date_str) |ds| {
        var tm: core.c.struct_tm = std.mem.zeroes(core.c.struct_tm);
        if (parseDate(ds, &tm)) {
            const t = core.c.timegm(&tm);
            ts[0].tv_sec = t;
            ts[0].tv_nsec = 0;
            ts[1].tv_sec = t;
            ts[1].tv_nsec = 0;
        }
    }

    if (atime and !mtime) ts[1].tv_nsec = UTIME_OMIT;
    if (mtime and !atime) ts[0].tv_nsec = UTIME_OMIT;

    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;

        const flags: c_int = if (no_deref) @intCast(core.c.AT_SYMLINK_NOFOLLOW) else 0;
        const result = core.c.utimensat(core.c.AT_FDCWD, &buf, &ts, flags);
        if (result == 0) continue;

        if (std.c._errno().* == ENOENT) {
            if (no_create) continue;
            const fd = core.c.open(&buf, core.c.O_RDWR | core.c.O_CREAT, @as(c_uint, 0o666));
            if (fd >= 0) {
                if (ref_file != null or date_str != null) {
                    _ = core.c.futimens(fd, &ts);
                }
                _ = core.c.close(fd);
                continue;
            }
        }
        core.eprint("touch: cannot touch '{s}'\n", .{args[i]});
        rc = 1;
    }
    return rc;
}

fn parseDate(s: []const u8, tm: *core.c.struct_tm) bool {
    if (s.len >= 12) {
        tm.tm_year = (std.fmt.parseInt(c_int, s[0..4], 10) catch return false) - 1900;
        tm.tm_mon = (std.fmt.parseInt(c_int, s[4..6], 10) catch return false) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, s[6..8], 10) catch return false;
        tm.tm_hour = std.fmt.parseInt(c_int, s[8..10], 10) catch return false;
        tm.tm_min = std.fmt.parseInt(c_int, s[10..12], 10) catch return false;
        if (s.len > 12 and s[12] == '.') {
            if (s.len >= 15) tm.tm_sec = std.fmt.parseInt(c_int, s[13..15], 10) catch return false;
        }
        return true;
    }
    if (s.len >= 10) {
        const yy = std.fmt.parseInt(c_int, s[0..2], 10) catch return false;
        tm.tm_year = if (yy >= 70) yy + 1900 - 1900 else yy + 2000 - 1900;
        tm.tm_mon = (std.fmt.parseInt(c_int, s[2..4], 10) catch return false) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, s[4..6], 10) catch return false;
        tm.tm_hour = std.fmt.parseInt(c_int, s[6..8], 10) catch return false;
        tm.tm_min = std.fmt.parseInt(c_int, s[8..10], 10) catch return false;
        if (s.len > 10 and s[10] == '.') {
            if (s.len >= 13) tm.tm_sec = std.fmt.parseInt(c_int, s[11..13], 10) catch return false;
        }
        return true;
    }
    if (s.len >= 8) {
        tm.tm_mon = (std.fmt.parseInt(c_int, s[0..2], 10) catch return false) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, s[2..4], 10) catch return false;
        tm.tm_hour = std.fmt.parseInt(c_int, s[4..6], 10) catch return false;
        tm.tm_min = std.fmt.parseInt(c_int, s[6..8], 10) catch return false;
        if (s.len > 8 and s[8] == '.') {
            if (s.len >= 11) tm.tm_sec = std.fmt.parseInt(c_int, s[9..11], 10) catch return false;
        }
        return true;
    }
    return false;
}
