const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "chrt", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 4) return 1;
    if (!std.mem.eql(u8, args[1], "-p")) return 1;
    const priority = std.fmt.parseInt(i32, args[2], 10) catch return 1;
    const pid = std.fmt.parseInt(c_int, args[3], 10) catch return 1;
    var param: core.c.struct_sched_param = undefined;
    param.sched_priority = @intCast(priority);
    if (core.c.sched_setscheduler(pid, core.c.SCHED_FIFO, &param) != 0) return 1;
    return 0;
}
