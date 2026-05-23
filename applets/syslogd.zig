const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "syslogd", .main = main };

pub fn main(_: [][]const u8) u8 {
    const paths = [_][]const u8{ "/var/log/syslog", "/var/log/messages" };
    for (paths) |path| {
        const fd = core.openReadName(path) orelse continue;
        defer _ = core.c.close(fd);
        const data = core.readAll(std.heap.page_allocator, fd, 65536) catch continue;
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
        return 0;
    }
    return core.die(1, "syslogd: no log files found\n", .{});
}
