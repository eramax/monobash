const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "strings", .main = main };

fn isPrintable(c: u8) bool {
    return c >= 32 and c <= 126;
}

pub fn main(args: [][]const u8) u8 {
    var min_len: usize = 4;
    var show_filename = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-n") or (arg.len > 2 and arg[1] == 'n')) {
            if (arg.len > 2) {
                min_len = std.fmt.parseUnsigned(usize, arg[2..], 10) catch
                    return core.die(1, "strings: invalid number: {s}\n", .{arg});
            } else {
                i += 1;
                if (i >= args.len) return core.die(1, "strings: option requires an argument: -n\n", .{});
                min_len = std.fmt.parseUnsigned(usize, args[i], 10) catch
                    return core.die(1, "strings: invalid number: {s}\n", .{args[i]});
            }
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| {
            switch (flag) {
                'f' => show_filename = true,
                else => return core.die(1, "strings: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    var exit_code: u8 = 0;

    if (files.len == 0) {
        const data = core.readAll(std.heap.page_allocator, 0, 1024 * 1024) catch return 1;
        defer std.heap.page_allocator.free(data);
        extractStrings(data, "", show_filename, min_len);
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("strings: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("strings: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);
        const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch {
            exit_code = 1;
            continue;
        };
        defer std.heap.page_allocator.free(data);
        extractStrings(data, f, show_filename, min_len);
    }

    return exit_code;
}

fn extractStrings(data: []const u8, filename: []const u8, show_name: bool, min_len: usize) void {
    var start: ?usize = null;
    var buf: [8192]u8 = undefined;

    for (data, 0..) |ch, i| {
        if (isPrintable(ch)) {
            if (start == null) start = i;
        } else {
            if (start) |s| {
                const len = i - s;
                if (len >= min_len) {
                    var pos: usize = 0;
                    if (show_name and filename.len > 0) {
                        const p = std.fmt.bufPrint(buf[pos..], "{s}: ", .{filename}) catch "";
                        pos += p.len;
                    }
                    const n = @min(len, buf.len - pos - 1);
                    @memcpy(buf[pos..][0..n], data[s..][0..n]);
                    pos += n;
                    buf[pos] = '\n';
                    core.writeAll(1, buf[0 .. pos + 1]);
                }
                start = null;
            }
        }
    }
    if (start) |s| {
        const len = data.len - s;
        if (len >= min_len) {
            var pos: usize = 0;
            if (show_name and filename.len > 0) {
                const p = std.fmt.bufPrint(buf[pos..], "{s}: ", .{filename}) catch "";
                pos += p.len;
            }
            const n = @min(len, buf.len - pos - 1);
            @memcpy(buf[pos..][0..n], data[s..][0..n]);
            pos += n;
            buf[pos] = '\n';
            core.writeAll(1, buf[0 .. pos + 1]);
        }
    }
}
