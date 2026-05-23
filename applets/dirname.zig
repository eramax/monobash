const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dirname", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const path = args[1];
    if (path.len == 0) {
        core.writeAll(1, ".\n");
        return 0;
    }
    var i: usize = path.len - 1;
    while (path[i] == '/') {
        if (i == 0) {
            core.writeAll(1, "/\n");
            return 0;
        }
        i -= 1;
    }
    while (path[i] != '/') {
        if (i == 0) {
            core.writeAll(1, ".\n");
            return 0;
        }
        i -= 1;
    }
    while (path[i] == '/') {
        if (i == 0) break;
        i -= 1;
    }
    core.writeAll(1, path[0 .. i + 1]);
    core.writeAll(1, "\n");
    return 0;
}
