const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "rm", .main = main };

fn removeEntry(path: [:0]const u8, recursive: bool, force: bool, verbose: bool) u8 {
    if (recursive) {
        const d = core.c.opendir(path.ptr);
        if (d) |dir| {
            defer _ = core.c.closedir(dir);
            var sub: [4096:0]u8 = undefined;
            while (true) {
                const entry = core.c.readdir(dir) orelse break;
                const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
                const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
                if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
                if (path.len + 1 + name.len >= sub.len) {
                    if (!force) return 1;
                    continue;
                }
                @memcpy(sub[0..path.len], path);
                sub[path.len] = '/';
                @memcpy(sub[path.len + 1 .. path.len + 1 + name.len], name);
                sub[path.len + 1 + name.len] = 0;
                if (removeEntry(sub[0..path.len + 1 + name.len :0], true, force, verbose) != 0 and !force)
                    return 1;
            }
            if (core.c.rmdir(path.ptr) != 0 and !force) return 1;
            if (verbose) core.eprint("rm: removed directory '{s}'\n", .{path});
            return 0;
        }
    }
    const rc = core.c.unlink(path.ptr);
    if (rc == 0) {
        if (verbose) core.eprint("rm: removed '{s}'\n", .{path});
        return 0;
    }
    if (force) return 0;
    return 1;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var recursive = false;
    var force = false;
    var verbose = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'r', 'R' => recursive = true,
                'f' => force = true,
                'v' => verbose = true,
                else => return 1,
            }
        }
        i += 1;
    }
    if (i >= args.len) {
        if (force) return 0;
        return 1;
    }
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;
        if (removeEntry(buf[0..args[i].len :0], recursive, force, verbose) != 0 and !force) {
            core.eprint("rm: cannot remove '{s}'\n", .{args[i]});
            rc = 1;
        }
    }
    return rc;
}
