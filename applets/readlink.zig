const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "readlink", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var canonicalize = false;
    var no_newline = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'f' => canonicalize = true,
                'n' => no_newline = true,
                else => return core.die(1, "readlink: invalid option\n", .{}),
            }
        }
        i += 1;
    }
    if (i >= args.len) return core.die(1, "usage: readlink FILE...\n", .{});
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var inbuf: [4096:0]u8 = undefined;
        if (args[i].len >= inbuf.len) { rc = 1; continue; }
        @memcpy(inbuf[0..args[i].len], args[i]);
        inbuf[args[i].len] = 0;
        if (canonicalize) {
            var outbuf: [4096:0]u8 = undefined;
            const res = core.c.realpath(&inbuf, &outbuf);
            if (res == null) { rc = 1; continue; }
            const len = std.mem.indexOfScalar(u8, &outbuf, 0) orelse outbuf.len;
            core.writeAll(1, outbuf[0..len]);
        } else {
            var outbuf: [4096]u8 = undefined;
            const n = core.c.readlink(&inbuf, &outbuf, outbuf.len);
            if (n < 0) { rc = 1; continue; }
            core.writeAll(1, outbuf[0..@intCast(n)]);
        }
        if (!no_newline) core.writeAll(1, "\n");
    }
    return rc;
}
