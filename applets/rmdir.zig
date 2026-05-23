const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "rmdir", .main = main };

fn removeDir(path: [:0]const u8, parents: bool) u8 {
    if (core.c.rmdir(path.ptr) != 0) return 1;
    if (parents) {
        var end = path.len;
        while (end > 0 and path[end - 1] == '/') { end -= 1; }
        if (end == 0) return 0;
        var slash: ?usize = null;
        var j: usize = 0;
        while (j < end) : (j += 1) {
            if (path[j] == '/') slash = j;
        }
        if (slash) |s| {
            if (s == 0) return 0;
            var buf: [4096:0]u8 = undefined;
            if (s >= buf.len) return 1;
            @memcpy(buf[0..s], path[0..s]);
            buf[s] = 0;
            _ = removeDir(buf[0..s :0], true);
        }
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var parents = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'p' => parents = true,
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
        if (removeDir(buf[0..args[i].len :0], parents) != 0) {
            core.eprint("rmdir: failed to remove '{s}'\n", .{args[i]});
            rc = 1;
        }
    }
    return rc;
}
