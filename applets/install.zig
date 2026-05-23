const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "install", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var mode: c_uint = 0o755;
    var owner: ?[]const u8 = null;
    var group: ?[]const u8 = null;
    var make_dirs = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i], "-d")) {
            make_dirs = true;
        } else if (std.mem.eql(u8, args[i][0..2], "-m")) {
            if (args[i].len > 2) {
                mode = std.fmt.parseInt(c_uint, args[i][2..], 8) catch 0o755;
            } else {
                i += 1;
                if (i < args.len) mode = std.fmt.parseInt(c_uint, args[i], 8) catch 0o755;
            }
        } else if (std.mem.eql(u8, args[i][0..2], "-o")) {
            if (args[i].len > 2) {
                owner = args[i][2..];
            } else {
                i += 1;
                if (i < args.len) owner = args[i];
            }
        } else if (std.mem.eql(u8, args[i][0..2], "-g")) {
            if (args[i].len > 2) {
                group = args[i][2..];
            } else {
                i += 1;
                if (i < args.len) group = args[i];
            }
        } else return core.die(1, "install: invalid option: {s}\n", .{args[i]});
        i += 1;
    }
    if (make_dirs) {
        var rc: u8 = 0;
        while (i < args.len) : (i += 1) {
            var buf: [4096:0]u8 = undefined;
            if (args[i].len >= buf.len) { rc = 1; continue; }
            @memcpy(buf[0..args[i].len], args[i]);
            buf[args[i].len] = 0;
            var path_buf: [4096]u8 = undefined;
            var pos: usize = 0;
            while (pos < args[i].len) {
                const slash = std.mem.indexOfScalar(u8, args[i][pos..], '/') orelse args[i].len - pos;
                pos += slash + 1;
                @memcpy(path_buf[0..pos], args[i][0..pos]);
                path_buf[pos] = 0;
                _ = core.c.mkdir(@as([*c]u8, @ptrCast(&path_buf)), mode);
            }
            if (core.c.mkdir(&buf, mode) != 0) {
                var statbuf: core.c.struct_stat = undefined;
                if (core.c.stat(&buf, &statbuf) != 0 or (statbuf.st_mode & core.c.S_IFMT) != core.c.S_IFDIR) {
                    core.eprint("install: cannot create directory '{s}'\n", .{args[i]});
                    rc = 1;
                }
            } else {
                _ = core.c.chmod(&buf, mode);
            }
        }
        return rc;
    }
    if (i + 1 >= args.len) {
        return core.die(1, "usage: install [-m MODE] [-o OWNER] [-g GROUP] FILE TARGET\n", .{});
    }
    const src = args[i];
    const dst = args[i + 1];
    var sbuf: [4096:0]u8 = undefined;
    if (src.len >= sbuf.len or dst.len >= sbuf.len) return 1;
    @memcpy(sbuf[0..src.len], src);
    sbuf[src.len] = 0;
    var dbuf: [4096:0]u8 = undefined;
    @memcpy(dbuf[0..dst.len], dst);
    dbuf[dst.len] = 0;
    const sfd = core.c.open(&sbuf, core.c.O_RDONLY);
    if (sfd < 0) return core.die(1, "install: {s}: No such file\n", .{src});
    defer _ = core.c.close(sfd);
    const dfd = core.c.open(&dbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, mode);
    if (dfd < 0) return core.die(1, "install: cannot create '{s}'\n", .{dst});
    defer _ = core.c.close(dfd);
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = core.c.read(sfd, &buf, buf.len);
        if (n <= 0) break;
        var pos: isize = 0;
        while (pos < n) {
            const w = core.c.write(dfd, buf[@as(usize, @intCast(pos))..].ptr, @as(usize, @intCast(n - pos)));
            if (w < 0) return core.die(1, "install: write error\n", .{});
            pos += w;
        }
    }
    _ = core.c.chmod(&dbuf, mode);
    if (owner) |o| {
        var obuf: [256:0]u8 = undefined;
        if (o.len >= obuf.len) return 1;
        @memcpy(obuf[0..o.len], o);
        obuf[o.len] = 0;
        const pw = core.c.getpwnam(&obuf);
        if (pw) |p| {
            _ = core.c.chown(&dbuf, p.*.pw_uid, @as(c_uint, @bitCast(@as(c_int, -1))));
        }
    }
    if (group) |g| {
        var gbuf: [256:0]u8 = undefined;
        if (g.len >= gbuf.len) return 1;
        @memcpy(gbuf[0..g.len], g);
        gbuf[g.len] = 0;
        const gr = core.c.getgrnam(&gbuf);
        if (gr) |gptr| {
            _ = core.c.chown(&dbuf, @as(c_uint, @bitCast(@as(c_int, -1))), gptr.*.gr_gid);
        }
    }
    return 0;
}
