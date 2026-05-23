const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dirname", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const path = args[1];
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }
    const trimmed = path[0..end];
    if (trimmed.len == 0) {
        core.writeAll(1, "/\n");
        return 0;
    }
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
    const dir = if (slash) |s| if (s == 0) "/" else trimmed[0..s] else ".";
    core.writeAll(1, dir);
    core.writeAll(1, "\n");
    return 0;
}
