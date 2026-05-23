const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tail", .main = main };

fn parseNum(s: []const u8) ?usize {
    return std.fmt.parseUnsigned(usize, s, 10) catch null;
}

pub fn main(args: [][]const u8) u8 {
    var n: usize = 10;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];
        if (arg.len > 2 and arg[1] == 'n') {
            n = parseNum(arg[2..]) orelse return core.die(1, "tail: invalid number: {s}\n", .{arg});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) return core.die(1, "tail: option requires an argument: -n\n", .{});
            n = parseNum(args[i]) orelse return core.die(1, "tail: invalid number: {s}\n", .{args[i]});
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| {
            switch (flag) {
                'n' => {},
                else => return core.die(1, "tail: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    var exit_code: u8 = 0;

    if (files.len == 0) {
        return tailFile(0, null, n);
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("tail: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("tail: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        if (files.len > 1) {
            var hbuf: [4096]u8 = undefined;
            const h = std.fmt.bufPrint(&hbuf, "==> {s} <==\n", .{f}) catch "";
            core.writeAll(1, h);
        }

        _ = tailFile(fd, null, n);
    }
    return exit_code;
}

fn tailFile(fd: c_int, _: ?[]const u8, n: usize) u8 {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return 1;
    defer std.heap.page_allocator.free(data);

    if (data.len == 0) return 0;

    var line_count: usize = 0;
    for (data) |ch| {
        if (ch == '\n') line_count += 1;
    }

    var start: usize = 0;
    var lines_skipped: usize = 0;
    if (line_count > n) {
        lines_skipped = line_count - n;
        var found: usize = 0;
        for (data, 0..) |ch, j| {
            if (ch == '\n') {
                found += 1;
                if (found == lines_skipped) {
                    start = j + 1;
                    break;
                }
            }
        }
    }

    core.writeAll(1, data[start..]);
    if (data.len > 0 and data[data.len - 1] != '\n') {
        core.writeAll(1, "\n");
    }
    return 0;
}
