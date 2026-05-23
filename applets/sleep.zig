const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sleep", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const n = std.fmt.parseUnsigned(u64, args[1], 10) catch return 1;
    _ = core.c.sleep(@intCast(n));
    return 0;
}
