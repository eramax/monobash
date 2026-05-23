const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "uniq", .main = main };

pub fn main(args: [][]const u8) u8 {
    var do_count = false;
    var case_insensitive = false;
    var only_duplicates = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'c' => do_count = true,
                'i' => case_insensitive = true,
                'd' => only_duplicates = true,
                else => return core.die(1, "uniq: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    if (files.len > 1) {
        return core.die(1, "uniq: extra operand: {s}\n", .{files[1]});
    }

    var opened_fd: c_int = 0;
    var need_close = false;
    const fd = if (files.len == 0) 0 else blk: {
        const f = files[0];
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return core.die(1, "uniq: path too long: {s}\n", .{f});
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd2 = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd2 < 0) return core.die(1, "uniq: {s}: No such file or directory\n", .{f});
        opened_fd = fd2;
        need_close = true;
        break :blk fd2;
    };
    defer {
        if (need_close) _ = core.c.close(opened_fd);
    }

    var reader = core.LineReader.init(fd);
    var prev: ?[]const u8 = null;
    var prev_owned: ?[]u8 = null;
    var count: usize = 1;

    while (reader.next()) |line| {
        if (prev) |p| {
            const same = if (case_insensitive)
                std.ascii.eqlIgnoreCase(p, line)
            else
                std.mem.eql(u8, p, line);

            if (same) {
                count += 1;
            } else {
                if (!only_duplicates or count > 1) {
                    outputLine(p, count, do_count);
                }
                count = 1;
                if (prev_owned) |po| {
                    std.heap.page_allocator.free(po);
                    prev_owned = null;
                }
                const dup = std.heap.page_allocator.dupe(u8, line) catch return 1;
                prev_owned = dup;
                prev = dup;
            }
        } else {
            const dup = std.heap.page_allocator.dupe(u8, line) catch return 1;
            prev_owned = dup;
            prev = dup;
        }
    }

    if (prev) |p| {
        if (!only_duplicates or count > 1) {
            outputLine(p, count, do_count);
        }
        if (prev_owned) |po| std.heap.page_allocator.free(po);
    }

    return 0;
}

fn outputLine(line: []const u8, count: usize, show_count: bool) void {
    var buf: [8192]u8 = undefined;
    if (show_count) {
        const s = std.fmt.bufPrint(&buf, "{d:>7} ", .{count}) catch "";
        core.writeAll(1, s);
        const remain = @min(line.len, buf.len - s.len - 1);
        @memcpy(buf[0..remain], line[0..remain]);
        core.writeAll(1, buf[0..remain]);
        core.writeAll(1, "\n");
    } else {
        const remain = @min(line.len, buf.len - 1);
        @memcpy(buf[0..remain], line[0..remain]);
        buf[remain] = '\n';
        core.writeAll(1, buf[0 .. remain + 1]);
    }
}

