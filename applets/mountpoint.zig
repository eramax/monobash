const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mountpoint", .main = main };

pub fn main(args: [][]const u8) u8 {
    var quiet = false;
    var print_device = false;
    var dir: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-q")) {
            quiet = true;
        } else if (std.mem.eql(u8, arg, "-d")) {
            print_device = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "mountpoint: invalid option '{s}'\n", .{arg});
        } else {
            dir = arg;
        }
    }

    const dir_path = dir orelse return core.die(1, "mountpoint: usage: mountpoint [-q] [-d] DIR\n", .{});

    var z_buf: [4096:0]u8 = undefined;
    if (dir_path.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..dir_path.len], dir_path);
    z_buf[dir_path.len] = 0;

    var dir_stat: core.c.struct_stat = undefined;
    if (core.c.stat(z_buf[0..dir_path.len :0].ptr, &dir_stat) != 0) {
        return core.die(1, "mountpoint: {s}: No such file or directory\n", .{dir_path});
    }

    // Get parent directory path
    const parent = if (std.mem.lastIndexOfScalar(u8, dir_path, '/')) |slash|
        if (slash == 0) "/" else dir_path[0..slash]
    else
        return core.die(1, "mountpoint: cannot determine parent\n", .{});

    if (parent.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..parent.len], parent);
    z_buf[parent.len] = 0;

    var parent_stat: core.c.struct_stat = undefined;
    if (core.c.stat(z_buf[0..parent.len :0].ptr, &parent_stat) != 0) {
        return core.die(1, "mountpoint: {s}: No such file or directory\n", .{parent});
    }

    const is_mountpoint = dir_stat.st_dev != parent_stat.st_dev;

    if (print_device) {
        var buf: [64]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{d}\n", .{@as(u64, @intCast(dir_stat.st_dev))}) catch return 1;
        core.writeAll(1, out);
        return if (is_mountpoint) 0 else 1;
    }

    if (quiet) {
        return if (is_mountpoint) 0 else 1;
    }

    if (is_mountpoint) {
        var buf: [4096]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{s} is a mountpoint\n", .{dir_path}) catch return 1;
        core.writeAll(1, out);
        return 0;
    } else {
        var buf: [4096]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{s} is not a mountpoint\n", .{dir_path}) catch return 1;
        core.writeAll(1, out);
        return 1;
    }
}
