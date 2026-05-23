const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "pathchk", .main = main };

fn isPortableChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-', '.', '/' => true,
        else => false,
    };
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var posix_mode = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'p' => posix_mode = true,
                else => return core.die(1, "pathchk: invalid option: -{c}\n", .{c}),
            }
        }
        i += 1;
    }
    if (i >= args.len) return core.die(1, "usage: pathchk [-p] PATH...\n", .{});
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        const path = args[i];
        if (posix_mode) {
            if (path.len > 255) {
                core.eprint("pathchk: '{s}': path too long (max 255 for POSIX)\n", .{path});
                rc = 1;
                continue;
            }
            for (path) |c| {
                if (!isPortableChar(c)) {
                    core.eprint("pathchk: '{s}': contains non-portable character\n", .{path});
                    rc = 1;
                    break;
                }
            }
            continue;
        }
        if (path.len > 4096) {
            core.eprint("pathchk: '{s}': path too long\n", .{path});
            rc = 1;
            continue;
        }
        if (path.len == 0) {
            core.eprint("pathchk: empty path name\n", .{});
            rc = 1;
            continue;
        }
        if (path[0] != '/') {
            var buf: [4096:0]u8 = undefined;
            if (core.c.getcwd(&buf, buf.len) == null) {
                rc = 1;
                continue;
            }
            const cwd = std.mem.sliceTo(&buf, 0);
            if (cwd.len + 1 + path.len >= 4096) {
                core.eprint("pathchk: '{s}': path too long when combined with cwd\n", .{path});
                rc = 1;
                continue;
            }
        }
        var pbuf: [4096:0]u8 = undefined;
        if (path.len >= pbuf.len) { rc = 1; continue; }
            @memcpy(pbuf[0..path.len], path);
        pbuf[path.len] = 0;
    }
    return rc;
}
