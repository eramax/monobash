const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "uptime", .main = main };
pub fn main(_: [][]const u8) u8 {
    const fd = core.c.open("/proc/uptime", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    var buf: [128]u8 = undefined;
    const n = core.c.read(fd, &buf, buf.len);
    if (n <= 0) return 1;
    const data = buf[0..@intCast(n)];
    const end = std.mem.indexOfAny(u8, data, " .\n") orelse data.len;
    const seconds = std.fmt.parseUnsigned(u64, data[0..end], 10) catch return 1;
    const days = seconds / 86400;
    const hours = (seconds % 86400) / 3600;
    const minutes = (seconds % 3600) / 60;
    var out: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&out, "up {} days, {} hours, {} minutes\n", .{ days, hours, minutes }) catch return 1;
    _ = core.c.write(1, s.ptr, s.len);
    return 0;
}
