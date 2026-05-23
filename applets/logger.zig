const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "logger", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: logger MESSAGE\n", .{});
    const alloc = std.heap.page_allocator;
    const msg = std.mem.join(alloc, " ", args[1..]) catch return 1;
    defer alloc.free(msg);
    const fd = core.c.open("/dev/kmsg", core.c.O_WRONLY);
    if (fd >= 0) {
        _ = core.c.write(fd, msg.ptr, msg.len);
        _ = core.c.write(fd, "\n", 1);
        _ = core.c.close(fd);
        return 0;
    }
    core.writeAll(2, "logger: ");
    core.writeAll(2, msg);
    core.writeAll(2, "\n");
    return 0;
}
