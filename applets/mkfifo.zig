const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mkfifo", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var mode: c_uint = 0o644;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i][0..2], "-m")) {
            if (args[i].len > 2) {
                mode = std.fmt.parseInt(c_uint, args[i][2..], 8) catch 0o644;
            } else {
                i += 1;
                if (i < args.len) mode = std.fmt.parseInt(c_uint, args[i], 8) catch 0o644;
            }
        }
        i += 1;
    }
    if (i >= args.len) return core.die(1, "usage: mkfifo [-m MODE] NAME...\n", .{});
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;
        if (core.c.mkfifo(&buf, mode) != 0) {
            core.eprint("mkfifo: cannot create fifo '{s}'\n", .{args[i]});
            rc = 1;
        }
    }
    return rc;
}
