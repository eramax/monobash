const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ipneigh", .main = main };

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/proc/net/arp", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return 1;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ' ');
        var field_idx: usize = 0;
        var ip: []const u8 = "";
        var hw: []const u8 = "";
        var dev: []const u8 = "";
        var state: []const u8 = "";

        while (fields.next()) |f| {
            if (f.len == 0) continue;
            switch (field_idx) {
                0 => ip = f,
                1 => hw = f,
                2 => state = f,
                3 => {},
                4 => {},
                5 => dev = f,
                else => {},
            }
            field_idx += 1;
        }

        var out: [256]u8 = undefined;
        const o = std.fmt.bufPrint(&out, "{s} dev {s} lladdr {s} {s}\n", .{ ip, dev, hw, state }) catch continue;
        core.writeAll(1, o);
    }
    return 0;
}
