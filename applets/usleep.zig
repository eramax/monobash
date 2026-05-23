const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "usleep", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const micros = std.fmt.parseUnsigned(u64, args[1], 10) catch return 1;
    const sec = micros / 1000000;
    const nsec = (micros % 1000000) * 1000;
    var ts = core.c.struct_timespec{ .tv_sec = @intCast(sec), .tv_nsec = @intCast(nsec) };
    _ = core.c.nanosleep(&ts, null);
    return 0;
}
