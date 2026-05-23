const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "crontab", .main = main };

pub fn main(args: [][]const u8) u8 {
    var list = false;
    var edit = false;
    var remove = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-l")) {
            list = true;
        } else if (std.mem.eql(u8, arg, "-e")) {
            edit = true;
        } else if (std.mem.eql(u8, arg, "-r")) {
            remove = true;
        } else {
            return core.die(1, "usage: crontab [-l|-e|-r]\n", .{});
        }
    }

    const pw = core.c.getpwuid(core.c.getuid());
    if (pw == null) return core.die(1, "crontab: cannot determine username\n", .{});
    const user = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0);

    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/var/spool/cron/crontabs/{s}", .{user}) catch return core.die(1, "crontab: path too long\n", .{});

    if (remove) {
        var zpath: [256:0]u8 = undefined;
        if (path.len >= zpath.len) return 1;
        @memcpy(zpath[0..path.len], path);
        zpath[path.len] = 0;
        _ = core.c.unlink(zpath[0..path.len :0].ptr);
        return 0;
    }

    if (edit) {
        return core.die(1, "crontab: -e not implemented\n", .{});
    }

    if (list) {
        var zpath: [256:0]u8 = undefined;
        if (path.len >= zpath.len) return 1;
        @memcpy(zpath[0..path.len], path);
        zpath[path.len] = 0;
        const fd = core.c.open(zpath[0..path.len :0].ptr, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "crontab: no crontab for '{s}'\n", .{user});
        defer _ = core.c.close(fd);
        const data = core.readAll(std.heap.page_allocator, fd, 65536) catch return 1;
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
        return 0;
    }

    return core.die(1, "usage: crontab [-l|-e|-r]\n", .{});
}
