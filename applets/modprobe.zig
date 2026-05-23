const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "modprobe", .main = main };

pub fn main(_: [][]const u8) u8 {
    const fd = core.openReadName("/proc/modules") orelse return core.die(1, "modprobe: cannot open /proc/modules\n", .{});
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 65536) catch return 1;
    defer std.heap.page_allocator.free(data);
    core.writeAll(1, data);
    return 0;
}
