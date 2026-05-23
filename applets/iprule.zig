const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "iprule", .main = main };

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/proc/net/rt_cache", core.c.O_RDONLY);
    if (fd < 0) {
        core.writeAll(1, "0: from all lookup local\n");
        core.writeAll(1, "32766: from all lookup main\n");
        core.writeAll(1, "32767: from all lookup default\n");
        return 0;
    }
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return 1;
    defer alloc.free(data);
    core.writeAll(1, data);
    return 0;
}
