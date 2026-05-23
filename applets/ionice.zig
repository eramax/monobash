const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "ionice", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 5) return 1;
    if (!std.mem.eql(u8, args[1], "-c")) return 1;
    const class = std.fmt.parseInt(u8, args[2], 10) catch return 1;
    if (!std.mem.eql(u8, args[3], "-p")) return 1;
    const pid = std.fmt.parseInt(c_int, args[4], 10) catch return 1;
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "/proc/{d}/ionice", .{pid}) catch return 1;
    const fd = core.c.open(path.ptr, core.c.O_WRONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    var data: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&data, "{d}:0\n", .{class}) catch return 1;
    core.writeAll(fd, s);
    return 0;
}
