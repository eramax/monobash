const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "find", .main = main };

fn wildcardMatch(pattern: []const u8, name: []const u8) bool {
    if (pattern.len == 0) return name.len == 0;
    if (pattern[0] == '*') {
        const rest = pattern[1..];
        if (rest.len == 0) return true;
        for (0..name.len) |i| {
            if (wildcardMatch(rest, name[i..])) return true;
        }
        return false;
    }
    if (name.len == 0) return false;
    if (pattern[0] == '?' or pattern[0] == name[0]) {
        return wildcardMatch(pattern[1..], name[1..]);
    }
    return false;
}

fn walkDir(path: [:0]const u8, depth: usize, name_pat: ?[]const u8, type_filter: ?u8, maxdepth: usize) u8 {
    if (depth > maxdepth) return 0;
    const d = core.c.opendir(path.ptr) orelse return 0;
    defer _ = core.c.closedir(d);

    var rc: u8 = 0;
    var sub_path: [4096:0]u8 = undefined;

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        if (path.len + 1 + name.len >= sub_path.len) continue;
        @memcpy(sub_path[0..path.len], path);
        sub_path[path.len] = '/';
        @memcpy(sub_path[path.len + 1 .. path.len + 1 + name.len], name);
        sub_path[path.len + 1 + name.len] = 0;
        const full_path = sub_path[0..path.len + 1 + name.len :0];

        var st: core.c.struct_stat = undefined;
        if (core.c.lstat(full_path.ptr, &st) != 0) continue;
        const is_dir = (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR;

        const matches_name = if (name_pat) |pat| wildcardMatch(pat, name) else true;
        const matches_type = if (type_filter) |tf| blk: {
            if (tf == 'f') break :blk !is_dir;
            if (tf == 'd') break :blk is_dir;
            break :blk true;
        } else true;

        if (depth > 0 and matches_name and matches_type) {
            const path_slice = full_path[0..full_path.len :0];
            core.writeAll(1, path_slice);
            core.writeAll(1, "\n");
        }

        if (is_dir) {
            if (walkDir(full_path, depth + 1, name_pat, type_filter, maxdepth) != 0)
                rc = 1;
        }
    }
    return rc;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "find: missing path\n", .{});
    var i: usize = 1;
    var name_pat: ?[]const u8 = null;
    var type_filter: ?u8 = null;
    var maxdepth: usize = std.math.maxInt(usize);
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-name") and i + 1 < args.len) {
            name_pat = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "-type") and i + 1 < args.len) {
            type_filter = args[i + 1][0];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "-maxdepth") and i + 1 < args.len) {
            maxdepth = std.fmt.parseInt(usize, args[i + 1], 10) catch std.math.maxInt(usize);
            i += 2;
        } else {
            i += 1;
        }
    }
    const start_path = args[1];
    var buf: [4096:0]u8 = undefined;
    if (start_path.len >= buf.len) return 1;
    @memcpy(buf[0..start_path.len], start_path);
    buf[start_path.len] = 0;
    return walkDir(buf[0..start_path.len :0], 0, name_pat, type_filter, maxdepth);
}
