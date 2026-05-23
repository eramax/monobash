const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "fsck", .main = main };

pub fn main(args: [][]const u8) u8 {
    var fstype: []const u8 = "";
    var _auto_repair = false;
    var _yes_all = false;
    var device: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-t") and i + 1 < args.len) {
            i += 1;
            fstype = args[i];
        } else if (std.mem.eql(u8, arg, "-a")) {
            _auto_repair = true;
        } else if (std.mem.eql(u8, arg, "-y")) {
            _yes_all = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "fsck: invalid option '{s}'\n", .{arg});
        } else {
            device = arg;
        }
    }

    const dev = device orelse return core.die(1, "fsck: usage: fsck [-t TYPE] [-a] [-y] DEVICE\n", .{});

    // Check if device exists
    var z_buf: [4096:0]u8 = undefined;
    const dev_path = if (std.mem.startsWith(u8, dev, "/dev/")) dev else blk: {
        const p = std.fmt.bufPrint(&z_buf, "/dev/{s}", .{dev}) catch return 1;
        @memcpy(z_buf[0..p.len], p);
        z_buf[p.len] = 0;
        break :blk z_buf[0..p.len :0];
    };

    var st: core.c.struct_stat = undefined;
    if (core.c.stat(dev_path.ptr, &st) != 0)
        return core.die(1, "fsck: cannot stat {s}': No such file or directory\n", .{dev_path});

    if (fstype.len > 0)
        core.writeAll(1, "fsck: ");
    core.writeAll(1, "fsck: not implemented yet\n");
    return 0;
}
