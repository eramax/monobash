const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ed", .main = main };

const LineArray = struct {
    lines: [][]u8,
    count: usize,
    capacity: usize,
};

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var buf: [4096]u8 = undefined;
    var lines: [4096][]u8 = undefined;
    var line_count: usize = 0;
    var current: usize = 0;

    if (args.len > 1) {
        var zpath: [4096:0]u8 = undefined;
        const path = args[1];
        if (path.len >= zpath.len) return core.die(1, "ed: path too long\n", .{});
        @memcpy(zpath[0..path.len], path);
        zpath[path.len] = 0;
        const fd = core.c.open(zpath[0..path.len :0].ptr, core.c.O_RDONLY);
        if (fd >= 0) {
            defer _ = core.c.close(fd);
            const data = core.readAll(std.heap.page_allocator, fd, buf.len) catch "";
            defer std.heap.page_allocator.free(data);
            var line_start: usize = 0;
            var i: usize = 0;
            while (i < data.len) : (i += 1) {
                if (data[i] == '\n') {
                    if (line_count < lines.len) {
                        const l = alloc.dupe(u8, data[line_start..i]) catch return 1;
                        lines[line_count] = l;
                        line_count += 1;
                    }
                    line_start = i + 1;
                }
            }
            if (line_start < data.len) {
                if (line_count < lines.len) {
                    const l = alloc.dupe(u8, data[line_start..]) catch return 1;
                    lines[line_count] = l;
                    line_count += 1;
                }
            }
            current = line_count;
        }
    }

    var cmd_buf: [4096]u8 = undefined;
    while (true) {
        core.writeAll(2, ": ");
        var pos: usize = 0;
        while (pos < cmd_buf.len) {
            var ch: u8 = 0;
            const n = core.c.read(0, @as([*]u8, @ptrCast(&ch)), 1);
            if (n <= 0) return 0;
            if (ch == '\n') break;
            cmd_buf[pos] = ch;
            pos += 1;
        }
        const cmd = cmd_buf[0..pos];

        if (cmd.len == 0) continue;

        if (std.mem.eql(u8, cmd, "q")) break;

        if (std.mem.eql(u8, cmd, "p")) {
            if (line_count == 0) {
                core.writeAll(2, "?\n");
                continue;
            }
            for (0..line_count) |i| {
                core.writeAll(1, lines[i]);
                core.writeAll(1, "\n");
            }
            continue;
        }

        if (std.mem.eql(u8, cmd, "n")) {
            for (0..line_count) |i| {
                var num_buf: [16]u8 = undefined;
                const num_str = std.fmt.bufPrint(&num_buf, "{}", .{i + 1}) catch "?";
                core.writeAll(1, num_str);
                core.writeAll(1, "\t");
                core.writeAll(1, lines[i]);
                core.writeAll(1, "\n");
            }
            continue;
        }

        if (std.mem.eql(u8, cmd, "w")) {
            if (args.len < 2) {
                core.writeAll(2, "?\n");
                continue;
            }
            var zpath: [4096:0]u8 = undefined;
            const path = args[1];
            if (path.len >= zpath.len) continue;
            @memcpy(zpath[0..path.len], path);
            zpath[path.len] = 0;
            const fd = core.c.open(zpath[0..path.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) {
                core.writeAll(2, "?\n");
                continue;
            }
            defer _ = core.c.close(fd);
            for (0..line_count) |i| {
                core.writeAll(fd, lines[i]);
                core.writeAll(fd, "\n");
            }
            continue;
        }

        if (std.mem.eql(u8, cmd, "a")) {
            core.writeAll(2, "enter text ('.' on line to end):\n");
            while (true) {
                var lpos: usize = 0;
                while (lpos < cmd_buf.len) {
                    var ch: u8 = 0;
                    const n = core.c.read(0, @as([*]u8, @ptrCast(&ch)), 1);
                    if (n <= 0) return 0;
                    if (ch == '\n') break;
                    cmd_buf[lpos] = ch;
                    lpos += 1;
                }
                const l = cmd_buf[0..lpos];
                if (std.mem.eql(u8, l, ".")) break;
                if (line_count < lines.len) {
                    lines[line_count] = alloc.dupe(u8, l) catch return 1;
                    line_count += 1;
                    current = line_count;
                }
            }
            continue;
        }

        if (std.mem.eql(u8, cmd, "i")) {
            core.writeAll(2, "enter text ('.' on line to end):\n");
            // Insert before current position
            const insert_pos = if (current > 0) current - 1 else @as(usize, 0);
            var new_lines: [4096][]u8 = undefined;
            var new_count: usize = 0;
            while (true) {
                var lpos: usize = 0;
                while (lpos < cmd_buf.len) {
                    var ch: u8 = 0;
                    const n = core.c.read(0, @as([*]u8, @ptrCast(&ch)), 1);
                    if (n <= 0) return 0;
                    if (ch == '\n') break;
                    cmd_buf[lpos] = ch;
                    lpos += 1;
                }
                if (std.mem.eql(u8, cmd_buf[0..lpos], ".")) break;
                if (new_count < new_lines.len) {
                    new_lines[new_count] = alloc.dupe(u8, cmd_buf[0..lpos]) catch return 1;
                    new_count += 1;
                }
            }
            if (new_count > 0) {
                // Shift existing lines right
                var shift = line_count;
                while (shift > insert_pos) : (shift -= 1) {
                    if (shift + new_count - 1 < lines.len) {
                        lines[shift + new_count - 1] = lines[shift - 1];
                    }
                }
                for (0..new_count) |j| {
                    lines[insert_pos + j] = new_lines[j];
                }
                line_count += new_count;
                current = insert_pos + new_count;
            }
            continue;
        }

        if (cmd.len > 1 and cmd[0] == '/') {
            const end = if (cmd[cmd.len - 1] == '/') cmd.len - 1 else cmd.len;
            const pat = cmd[1..end];
            var found = false;
            for (0..line_count) |i| {
                if (std.mem.indexOf(u8, lines[i], pat) != null) {
                    core.writeAll(1, lines[i]);
                    core.writeAll(1, "\n");
                    current = i + 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                core.writeAll(2, "?\n");
            }
            continue;
        }

        core.writeAll(2, "?\n");
    }

    for (0..line_count) |i| alloc.free(lines[i]);
    return 0;
}
