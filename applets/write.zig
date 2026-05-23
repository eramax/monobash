const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "write", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: write USER TTY\n", .{});
    var buf: [4096:0]u8 = undefined;
    const tty_path = std.fmt.bufPrint(&buf, "/dev/pts/{s}", .{args[2]}) catch {
        return core.die(1, "write: invalid tty\n", .{});
    };
    var path_buf: [4096:0]u8 = undefined;
    if (tty_path.len >= path_buf.len) return 1;
    @memcpy(path_buf[0..tty_path.len], tty_path);
    path_buf[tty_path.len] = 0;
    const fd = core.c.open(&path_buf, core.c.O_WRONLY);
    if (fd < 0) return core.die(1, "write: cannot open tty\n", .{});
    defer _ = core.c.close(fd);
    while (true) {
        const data = core.readAll(std.heap.page_allocator, 0, 1024) catch break;
        defer std.heap.page_allocator.free(data);
        if (data.len == 0) break;
        core.writeAll(fd, data);
    }
    return 0;
}
