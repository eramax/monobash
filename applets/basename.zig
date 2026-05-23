const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "basename", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const path = args[1];
    const suffix = if (args.len > 2) args[2] else "";
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }
    const trimmed = path[0..end];
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
    const base = if (slash) |s| trimmed[s + 1 ..] else trimmed;
    const result = if (suffix.len > 0 and base.len > suffix.len and std.mem.endsWith(u8, base, suffix)) base[0 .. base.len - suffix.len] else base;
    core.writeAll(1, result);
    core.writeAll(1, "\n");
    return 0;
}
