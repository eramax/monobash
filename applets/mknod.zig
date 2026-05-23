const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mknod", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var mode: c_uint = 0o666;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i][0..2], "-m")) {
            if (args[i].len > 2) {
                mode = std.fmt.parseInt(c_uint, args[i][2..], 8) catch 0o666;
            } else {
                i += 1;
                if (i < args.len) mode = std.fmt.parseInt(c_uint, args[i], 8) catch 0o666;
            }
        }
        i += 1;
    }
    if (i + 2 >= args.len) return core.die(1, "usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]\n", .{});
    var buf: [4096:0]u8 = undefined;
    if (args[i].len >= buf.len) return 1;
    @memcpy(buf[0..args[i].len], args[i]);
    buf[args[i].len] = 0;
    const name = &buf;
    i += 1;
    if (args[i].len != 1) return core.die(1, "mknod: type must be b, c, or p\n", .{});
    const typ = args[i][0];
    i += 1;
    var rc: u8 = 0;
    switch (typ) {
        'p' => {
            if (core.c.mkfifo(name, mode) != 0) {
                core.eprint("mknod: cannot create fifo '{s}'\n", .{args[1]});
                rc = 1;
            }
        },
        'b', 'c' => {
            if (i + 1 >= args.len) return core.die(1, "mknod: missing major/minor numbers\n", .{});
            const major = std.fmt.parseInt(u64, args[i], 10) catch {
                core.eprint("mknod: invalid major number '{s}'\n", .{args[i]});
                return 1;
            };
            const minor = std.fmt.parseInt(u64, args[i + 1], 10) catch {
                core.eprint("mknod: invalid minor number '{s}'\n", .{args[i + 1]});
                return 1;
            };
            const dev = (major << 20) | minor;
            const stat_mode = if (typ == 'b') @as(c_uint, core.c.S_IFBLK) | mode else @as(c_uint, core.c.S_IFCHR) | mode;
            if (core.c.mknod(name, stat_mode, @as(c_uint, @intCast(dev))) != 0) {
                core.eprint("mknod: cannot create node '{s}'\n", .{args[1]});
                rc = 1;
            }
        },
        else => return core.die(1, "mknod: type must be b, c, or p\n", .{}),
    }
    return rc;
}
