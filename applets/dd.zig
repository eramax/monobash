const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dd", .main = main };

fn parseNum(s: []const u8) ?usize {
    if (s.len == 0) return null;
    var val: usize = 0;
    var i: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') {
        val = val *% 10 +% @as(usize, @intCast(s[i] - '0'));
        i += 1;
    }
    if (i == 0) return null;
    if (i < s.len) {
        const suffix = s[i];
        if (suffix == 'k' or suffix == 'K') {
            val *%= 1024;
        } else if (suffix == 'M') {
            val *%= 1024 * 1024;
        } else if (suffix == 'G') {
            val *%= 1024 * 1024 * 1024;
        } else if (suffix == 'w') {
            val *%= 2;
        } else if (suffix == 'b') {
            val *%= 512;
        }
    }
    return val;
}

pub fn main(args: [][]const u8) u8 {
    var if_name: ?[]const u8 = null;
    var of_name: ?[]const u8 = null;
    var bs: usize = 512;
    var count: ?usize = null;
    var skip: usize = 0;
    var seek: usize = 0;

    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const key = arg[0..eq];
            const val = arg[eq + 1 ..];
            if (std.mem.eql(u8, key, "if")) {
                if_name = val;
            } else if (std.mem.eql(u8, key, "of")) {
                of_name = val;
            } else if (std.mem.eql(u8, key, "bs")) {
                bs = parseNum(val) orelse 512;
            } else if (std.mem.eql(u8, key, "count")) {
                count = parseNum(val);
            } else if (std.mem.eql(u8, key, "skip")) {
                skip = parseNum(val) orelse 0;
            } else if (std.mem.eql(u8, key, "seek")) {
                seek = parseNum(val) orelse 0;
            }
        }
    }

    var in_fd: c_int = 0;
    var in_owned = false;
    if (if_name) |name| {
        var buf: [4096:0]u8 = undefined;
        if (name.len >= buf.len) return 1;
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        in_fd = core.c.open(buf[0..name.len :0].ptr, core.c.O_RDONLY);
        if (in_fd < 0) return core.die(1, "dd: cannot open '{s}'\n", .{name});
        in_owned = true;
    }

    var out_fd: c_int = 1;
    var out_owned = false;
    if (of_name) |name| {
        var buf: [4096:0]u8 = undefined;
        if (name.len >= buf.len) { if (in_owned) _ = core.c.close(in_fd); return 1; }
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        out_fd = core.c.open(buf[0..name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
        if (out_fd < 0) {
            if (in_owned) _ = core.c.close(in_fd);
            return core.die(1, "dd: cannot open '{s}'\n", .{name});
        }
        out_owned = true;
    }

    defer {
        if (in_owned) _ = core.c.close(in_fd);
        if (out_owned) _ = core.c.close(out_fd);
    }

    // Skip input blocks
    if (skip > 0) {
        if (core.c.lseek(in_fd, @as(isize, @intCast(skip * bs)), core.c.SEEK_SET) < 0) {
            const alloc = std.heap.page_allocator;
            var remain = skip * bs;
            while (remain > 0) {
                const data = core.readAll(alloc, in_fd, @min(remain, @as(usize, 4096))) catch break;
                defer alloc.free(data);
                if (data.len == 0) break;
                remain -|= data.len;
            }
        }
    }

    // Seek output
    if (seek > 0) {
        _ = core.c.lseek(out_fd, @as(isize, @intCast(seek * bs)), core.c.SEEK_SET);
    }

    var written: usize = 0;
    var blocks: usize = 0;

    while (true) {
        if (count) |c| {
            if (blocks >= c) break;
        }
        const to_read = @min(bs, @as(usize, 65536));
        const alloc = std.heap.page_allocator;
        const data = core.readAll(alloc, in_fd, to_read) catch break;
        defer alloc.free(data);
        if (data.len == 0) break;
        core.writeAll(out_fd, data);
        written += data.len;
        if (data.len == to_read) blocks += 1;
        if (data.len < bs) break;
    }

    // Report summary to stderr
    core.eprint("dd: {} bytes copied, {} blocks\n", .{ written, blocks });
    return 0;
}
