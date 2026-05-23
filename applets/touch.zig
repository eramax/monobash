const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "touch", .main = main };

fn touchFile(path: [:0]const u8, atime: bool, mtime: bool) u8 {
    const fd = core.c.open(path.ptr, core.c.O_RDWR | core.c.O_CREAT, @as(c_uint, 0o666));
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    if (!atime and !mtime) {
        _ = core.c.futimens(fd, null);
    } else if (atime and mtime) {
        _ = core.c.futimens(fd, null);
    } else {
        const UTIME_NOW: i64 = 1073741823;
        const UTIME_OMIT: i64 = 1073741822;
        var ts: [2]core.c.struct_timespec = undefined;
        ts[0].tv_sec = 0;
        ts[0].tv_nsec = if (atime) UTIME_NOW else UTIME_OMIT;
        ts[1].tv_sec = 0;
        ts[1].tv_nsec = if (mtime) UTIME_NOW else UTIME_OMIT;
        _ = core.c.futimens(fd, &ts);
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var atime = false;
    var mtime = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'a' => atime = true,
                'm' => mtime = true,
                else => return 1,
            }
        }
        i += 1;
    }
    if (i >= args.len) return 1;
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;
        if (touchFile(buf[0..args[i].len :0], atime, mtime) != 0) {
            core.eprint("touch: cannot touch '{s}'\n", .{args[i]});
            rc = 1;
        }
    }
    return rc;
}
