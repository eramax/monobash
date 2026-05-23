const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "head", .main = main };

fn parseNum(s: []const u8) ?usize {
    return std.fmt.parseUnsigned(usize, s, 10) catch null;
}

pub fn main(args: [][]const u8) u8 {
    var n: usize = 10;
    var c_mode = false;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];
        if (arg.len > 2 and arg[1] == 'n') {
            c_mode = false;
            n = parseNum(arg[2..]) orelse return core.die(1, "head: invalid number: {s}\n", .{arg});
            i += 1;
            continue;
        }
        if (arg.len > 2 and arg[1] == 'c') {
            c_mode = true;
            n = parseNum(arg[2..]) orelse return core.die(1, "head: invalid number: {s}\n", .{arg});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-n")) {
            c_mode = false;
            i += 1;
            if (i >= args.len) return core.die(1, "head: option requires an argument: -n\n", .{});
            n = parseNum(args[i]) orelse return core.die(1, "head: invalid number: {s}\n", .{args[i]});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-c")) {
            c_mode = true;
            i += 1;
            if (i >= args.len) return core.die(1, "head: option requires an argument: -c\n", .{});
            n = parseNum(args[i]) orelse return core.die(1, "head: invalid number: {s}\n", .{args[i]});
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| {
            switch (flag) {
                'n' => c_mode = false,
                'c' => c_mode = true,
                else => return core.die(1, "head: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    var exit_code: u8 = 0;

    if (files.len == 0) {
        if (c_mode) {
            const buf = core.readAll(std.heap.page_allocator, 0, 1024 * 1024) catch return 1;
            defer std.heap.page_allocator.free(buf);
            core.writeAll(1, buf[0..@min(n, buf.len)]);
        } else {
            var reader = core.LineReader.init(0);
            var count: usize = 0;
            while (reader.next()) |line| {
                if (count >= n) break;
                core.writeAll(1, line);
                core.writeAll(1, "\n");
                count += 1;
            }
        }
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("head: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("head: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        if (files.len > 1) {
            var hbuf: [4096]u8 = undefined;
            const h = std.fmt.bufPrint(&hbuf, "==> {s} <==\n", .{f}) catch "";
            core.writeAll(1, h);
        }

        if (c_mode) {
            const buf = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch {
                exit_code = 1;
                continue;
            };
            defer std.heap.page_allocator.free(buf);
            core.writeAll(1, buf[0..@min(n, buf.len)]);
        } else {
            var reader = core.LineReader.init(fd);
            var count: usize = 0;
            while (reader.next()) |line| {
                if (count >= n) break;
                core.writeAll(1, line);
                core.writeAll(1, "\n");
                count += 1;
            }
        }
    }
    return exit_code;
}
