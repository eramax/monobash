const std = @import("std");
const core = @import("core.zig");
const VT_GETSTATE: u32 = 0x5603;
pub const meta = core.AppletMeta{ .name = "fgconsole", .main = main };
pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/dev/console", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "fgconsole: cannot open /dev/console\n", .{});
    defer _ = core.c.close(fd);
    var vs: [6]u8 = undefined;
    if (core.c.ioctl(fd, VT_GETSTATE, &vs) < 0)
        return core.die(1, "fgconsole: VT_GETSTATE failed\n", .{});
    const active = std.mem.readInt(u16, vs[0..2], .little);
    const msg = std.fmt.allocPrint(alloc, "{d}\n", .{active}) catch return 1;
    defer alloc.free(msg);
    core.writeAll(1, msg);
    return 0;
}
