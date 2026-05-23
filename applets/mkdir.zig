const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mkdir", .main = main };

fn makeDir(path: [:0]const u8, parents: bool, verbose: bool) u8 {
    if (parents) {
        var buf: [4096:0]u8 = undefined;
        var i: usize = if (path.len > 0 and path[0] == '/') @as(usize, 1) else @as(usize, 0);
        while (i < path.len) : (i += 1) {
            if (path[i] == '/') {
                if (i >= buf.len) return 1;
                @memcpy(buf[0..i], path[0..i]);
                buf[i] = 0;
                const rc = core.c.mkdir(buf[0..i :0].ptr, 0o755);
                if (rc != 0) {
                    var st: core.c.struct_stat = undefined;
                    if (core.c.stat(buf[0..i :0].ptr, &st) != 0) return 1;
                    if ((st.st_mode & core.c.S_IFMT) != core.c.S_IFDIR) return 1;
                } else if (verbose) {
                    core.eprint("mkdir: created directory '{s}'\n", .{buf[0..i]});
                }
            }
        }
    }
    const rc = core.c.mkdir(path.ptr, 0o755);
    if (rc == 0) {
        if (verbose) core.eprint("mkdir: created directory '{s}'\n", .{path});
        return 0;
    }
    if (parents) {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(path.ptr, &st) == 0 and (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) return 0;
    }
    return 1;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var parents = false;
    var verbose = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'p' => parents = true,
                'v' => verbose = true,
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
        if (makeDir(buf[0..args[i].len :0], parents, verbose) != 0) {
            core.eprint("mkdir: cannot create directory '{s}': error\n", .{args[i]});
            rc = 1;
        }
    }
    return rc;
}
