const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "printenv", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) {
        var i: usize = 0;
        while (core.environ[i]) |entry| {
            const s = std.mem.sliceTo(entry, 0);
            core.writeAll(1, s);
            core.writeAll(1, "\n");
            i += 1;
        }
        return 0;
    }
    var exit_code: u8 = 0;
    for (args[1..]) |name| {
        var buf: [4096:0]u8 = undefined;
        if (name.len >= buf.len) {
            exit_code = 1;
            continue;
        }
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        const val = core.c.getenv(&buf);
        if (val) |v| {
            const s = std.mem.sliceTo(v, 0);
            core.writeAll(1, s);
            core.writeAll(1, "\n");
        } else {
            exit_code = 1;
        }
    }
    return exit_code;
}
