const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tty", .main = main };

pub fn main(args: [][]const u8) u8 {
    var silent = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            silent = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            break;
        } else if (arg.len > 0 and arg[0] == '-') {
            return core.die(1, "tty: invalid option: {s}\n", .{arg});
        }
    }
    const name = core.c.ttyname(0);
    if (name) |ptr| {
        if (!silent) {
            const len = std.mem.indexOfScalar(u8, std.mem.sliceTo(ptr, 0), 0) orelse 0;
            core.writeAll(1, ptr[0..len]);
            core.writeAll(1, "\n");
        }
        return 0;
    }
    if (!silent) core.writeAll(1, "not a tty\n");
    return 1;
}
