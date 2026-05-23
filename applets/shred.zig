const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "shred", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var passes: usize = 3;
    var remove = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i][0..2], "-n")) {
            if (args[i].len > 2) {
                passes = std.fmt.parseInt(usize, args[i][2..], 10) catch 3;
            } else {
                i += 1;
                if (i < args.len) passes = std.fmt.parseInt(usize, args[i], 10) catch 3;
            }
        } else if (std.mem.eql(u8, args[i], "-u")) {
            remove = true;
        }
        i += 1;
    }
    if (i >= args.len) return core.die(1, "usage: shred [-n N] [-u] FILE...\n", .{});
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;
        const fd = core.c.open(&buf, core.c.O_WRONLY);
        if (fd < 0) { rc = 1; continue; }
        const st = core.c.lseek(fd, 0, 2);
        if (st > 0) {
            _ = core.c.lseek(fd, 0, 0);
            var seed: u64 = 12345;
            var pass: usize = 0;
            while (pass < passes) : (pass += 1) {
                _ = core.c.lseek(fd, 0, 0);
                var written: i64 = 0;
                while (written < st) {
                    var randbuf: [8192]u8 = undefined;
                    for (&randbuf) |*b| {
                        seed = seed *% 1103515245 +% 12345;
                        b.* = @as(u8, @truncate(seed >> 16));
                    }
                    const remaining = st - written;
                    const to_write = @min(randbuf.len, @as(usize, @intCast(remaining)));
                    const n = core.c.write(fd, &randbuf, to_write);
                    if (n < 0) break;
                    written += @as(i64, @intCast(n));
                }
            }
        }
        _ = core.c.close(fd);
        if (remove) _ = core.c.unlink(&buf);
    }
    return rc;
}
