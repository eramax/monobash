const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tac", .main = main };

pub fn main(args: [][]const u8) u8 {
    const files = args[1..];
    const alloc = std.heap.page_allocator;

    if (files.len == 0) {
        var lines: std.ArrayListAligned([]const u8, null) = .empty;
        defer lines.deinit(alloc);
        var reader = core.LineReader.init(0);
        while (reader.next()) |line| {
            const dup = alloc.dupe(u8, line) catch return 1;
            lines.append(alloc, dup) catch return 1;
        }
        var i: usize = lines.items.len;
        var buf: [8192]u8 = undefined;
        while (i > 0) {
            i -= 1;
            const n = @min(lines.items[i].len, buf.len - 1);
            @memcpy(buf[0..n], lines.items[i][0..n]);
            buf[n] = '\n';
            core.writeAll(1, buf[0 .. n + 1]);
        }
        return 0;
    }

    var exit_code: u8 = 0;
    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("tac: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("tac: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        const data = core.readAll(alloc, fd, 1024 * 1024) catch {
            exit_code = 1;
            continue;
        };
        defer alloc.free(data);

        var line_ends: std.ArrayListAligned(usize, null) = .empty;
        defer line_ends.deinit(alloc);
        for (data, 0..) |ch, j| {
            if (ch == '\n') line_ends.append(alloc, j) catch return 1;
        }

        var buf: [8192]u8 = undefined;
        if (line_ends.items.len == 0) {
            const n = @min(data.len, buf.len - 1);
            @memcpy(buf[0..n], data[0..n]);
            buf[n] = '\n';
            core.writeAll(1, buf[0 .. n + 1]);
        } else {
            var prev_end: usize = data.len;
            var li: usize = line_ends.items.len;
            while (li > 0) {
                li -= 1;
                const le = line_ends.items[li];
                const line = data[le + 1 .. prev_end];
                prev_end = le;
                const n = @min(line.len, buf.len - 1);
                @memcpy(buf[0..n], line[0..n]);
                buf[n] = '\n';
                core.writeAll(1, buf[0 .. n + 1]);
            }
            const first = data[0..prev_end];
            if (first.len > 0) {
                const n = @min(first.len, buf.len - 1);
                @memcpy(buf[0..n], first[0..n]);
                buf[n] = '\n';
                core.writeAll(1, buf[0 .. n + 1]);
            }
        }
    }

    return exit_code;
}
