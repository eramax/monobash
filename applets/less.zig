const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "less", .main = main };

pub fn main(args: [][]const u8) u8 {
    const files = args[1..];
    var exit_code: u8 = 0;

    if (files.len == 0) {
        const data = core.readAll(std.heap.page_allocator, 0, 1024 * 1024) catch return 1;
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("less: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("less: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch {
            exit_code = 1;
            continue;
        };
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
    }

    return exit_code;
}
