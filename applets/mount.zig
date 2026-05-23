const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mount", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/proc/mounts", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return 1;
    defer alloc.free(data);
    var iter = std.mem.splitScalar(u8, data, '\n');
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ' ');
        const dev = fields.next() orelse "";
        const mountpoint = fields.next() orelse "";
        const fstype = fields.next() orelse "";
        const opts = fields.next() orelse "";
        var out: [1024]u8 = undefined;
        const formatted = std.fmt.bufPrint(&out, "{s} on {s} type {s} ({s})\n", .{ dev, mountpoint, fstype, opts }) catch continue;
        core.writeAll(1, formatted);
    }
    return 0;
}
