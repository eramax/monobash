const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "df", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const fd = core.c.open("/proc/mounts", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return 1;
    defer alloc.free(data);

    core.writeAll(1, "Filesystem     1K-blocks      Used   Available Use% Mounted on\n");

    var iter = std.mem.splitScalar(u8, data, '\n');
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ' ');
        const dev = fields.next() orelse "";
        const mountpoint = fields.next() orelse "";
        _ = fields.next();
        _ = fields.next();

        var z_buf: [4096:0]u8 = undefined;
        if (mountpoint.len >= z_buf.len) continue;
        @memcpy(z_buf[0..mountpoint.len], mountpoint);
        z_buf[mountpoint.len] = 0;

        var vfs: core.c.struct_statvfs = undefined;
        if (core.c.statvfs(z_buf[0..mountpoint.len :0].ptr, &vfs) != 0) continue;

        const frsize = @as(u64, @intCast(vfs.f_frsize));
        const blocks = @as(u64, @intCast(vfs.f_blocks)) * frsize / 1024;
        const bfree = @as(u64, @intCast(vfs.f_bfree)) * frsize / 1024;
        const bavail = @as(u64, @intCast(vfs.f_bavail)) * frsize / 1024;
        const used = blocks - bfree;
        const pct = if (blocks > 0) @divTrunc(used * 100, blocks) else 0;

        var out: [1024]u8 = undefined;
        const formatted = std.fmt.bufPrint(&out, "{s:<14} {d:>10} {d:>10} {d:>10} {d:>3}% {s}\n",
            .{ dev, blocks, used, bavail, pct, mountpoint }) catch continue;
        core.writeAll(1, formatted);
    }

    return 0;
}
