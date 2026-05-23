const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "renice", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 5) return 1;
    if (!std.mem.eql(u8, args[1], "-n")) return 1;
    const adj = std.fmt.parseInt(i32, args[2], 10) catch return 1;
    if (!std.mem.eql(u8, args[3], "-p")) return 1;
    const pid = std.fmt.parseInt(c_uint, args[4], 10) catch return 1;
    if (core.c.setpriority(core.c.PRIO_PROCESS, pid, adj) != 0) return 1;
    return 0;
}
