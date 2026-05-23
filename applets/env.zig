const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "env", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    var i: usize = 0;
    while (core.environ[i]) |entry| {
        const s = std.mem.sliceTo(entry, 0);
        core.writeAll(1, s);
        core.writeAll(1, "\n");
        i += 1;
    }
    return 0;
}
