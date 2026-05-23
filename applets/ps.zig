const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ps", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const d = core.c.opendir("/proc") orelse return 1;
    defer _ = core.c.closedir(d);

    core.writeAll(1, "  PID CMD                         STAT\n");

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);

        const pid = std.fmt.parseInt(usize, name, 10) catch continue;

        var path_buf: [64]u8 = undefined;
        const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch continue;
        var z_buf: [256:0]u8 = undefined;
        if (stat_path.len >= z_buf.len) continue;
        @memcpy(z_buf[0..stat_path.len], stat_path);
        z_buf[stat_path.len] = 0;

        const fd = core.c.open(z_buf[0..stat_path.len :0].ptr, core.c.O_RDONLY);
        if (fd < 0) continue;
        defer _ = core.c.close(fd);

        const data = core.readAll(alloc, fd, 4096) catch continue;
        defer alloc.free(data);

        const open_paren = std.mem.indexOfScalar(u8, data, '(') orelse continue;
        const close_paren = std.mem.lastIndexOfScalar(u8, data, ')') orelse continue;
        const comm = data[open_paren + 1 .. close_paren];
        const rest = data[close_paren + 2 ..];
        const state = if (rest.len > 0) rest[0..1] else "?";

        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{d:>5} {s:<28} {s}\n", .{ pid, comm, state }) catch continue;
        core.writeAll(1, line);
    }

    return 0;
}
