const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "grep", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var case_insensitive = false;
    var invert = false;
    var do_count = false;
    var do_lnum = false;
    var extended = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            break;
        }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'i' => case_insensitive = true,
                'v' => invert = true,
                'c' => do_count = true,
                'n' => do_lnum = true,
                'E' => extended = true,
                else => return core.die(2, "grep: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(2, "grep: missing pattern\n", .{});
    const pattern = args[i];
    i += 1;
    const files = args[i..];

    var pat_buf: [4096:0]u8 = undefined;
    if (pattern.len >= pat_buf.len) return core.die(2, "grep: pattern too long\n", .{});
    @memcpy(pat_buf[0..pattern.len], pattern);
    pat_buf[pattern.len] = 0;

    var regex_buf: [1024]u8 align(@alignOf(c_int)) = undefined;
    const regex: *core.c.regex_t = @ptrCast(&regex_buf);

    var cflags: c_int = core.c.REG_NOSUB;
    if (case_insensitive) cflags |= core.c.REG_ICASE;
    if (extended) cflags |= core.c.REG_EXTENDED;

    if (core.c.regcomp(regex, &pat_buf, cflags) != 0) return core.die(2, "grep: invalid pattern\n", .{});
    defer core.c.regfree(regex);

    var matched: usize = 0;
    var err = false;

    if (files.len == 0) {
        matched = grepFile(0, null, regex, invert, do_count, do_lnum);
    } else {
        for (files) |f| {
            var fbuf: [4096:0]u8 = undefined;
            if (f.len >= fbuf.len) {
                core.eprint("grep: {s}: path too long\n", .{f});
                err = true;
                continue;
            }
            @memcpy(fbuf[0..f.len], f);
            fbuf[f.len] = 0;
            const fd = core.c.open(&fbuf, core.c.O_RDONLY);
            if (fd < 0) {
                core.eprint("grep: {s}: No such file or directory\n", .{f});
                err = true;
                continue;
            }
            defer _ = core.c.close(fd);
            matched += grepFile(fd, if (files.len > 1) f else null, regex, invert, do_count, do_lnum);
        }
    }

    if (matched > 0) return 0;
    return if (err) 2 else 1;
}

fn grepFile(fd: c_int, name: ?[]const u8, regex: *core.c.regex_t, invert: bool, do_count: bool, do_lnum: bool) usize {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return 0;
    defer std.heap.page_allocator.free(data);

    var lnum: usize = 0;
    var matched: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;
    var lbuf: [65536]u8 = undefined;

    while (i < data.len) {
        if (data[i] == '\n') {
            lnum += 1;
            const line = data[line_start..i];
            if (line.len < lbuf.len) {
                @memcpy(lbuf[0..line.len], line);
                lbuf[line.len] = 0;

                const match = core.c.regexec(regex, &lbuf, 0, null, 0) == 0;
                const show = if (invert) !match else match;

                if (show) {
                    matched += 1;
                    if (!do_count) {
                        var obuf: [8192]u8 = undefined;
                        var pos: usize = 0;
                        if (name) |n| {
                            const p = std.fmt.bufPrint(obuf[pos..], "{s}:", .{n}) catch "";
                            pos += p.len;
                        }
                        if (do_lnum) {
                            const p = std.fmt.bufPrint(obuf[pos..], "{d}:", .{lnum}) catch "";
                            pos += p.len;
                        }
                        const remain = @min(line.len, obuf.len - pos - 1);
                        @memcpy(obuf[pos..][0..remain], line[0..remain]);
                        pos += remain;
                        obuf[pos] = '\n';
                        core.writeAll(1, obuf[0 .. pos + 1]);
                    }
                }
            }
            line_start = i + 1;
        }
        i += 1;
    }

    // Handle last line without trailing newline
    if (line_start < data.len) {
        lnum += 1;
        const line = data[line_start..];
        if (line.len < lbuf.len) {
            @memcpy(lbuf[0..line.len], line);
            lbuf[line.len] = 0;

            const match = core.c.regexec(regex, &lbuf, 0, null, 0) == 0;
            const show = if (invert) !match else match;

            if (show) {
                matched += 1;
                if (!do_count) {
                    var obuf: [8192]u8 = undefined;
                    var pos: usize = 0;
                    if (name) |n| {
                        const p = std.fmt.bufPrint(obuf[pos..], "{s}:", .{n}) catch "";
                        pos += p.len;
                    }
                    if (do_lnum) {
                        const p = std.fmt.bufPrint(obuf[pos..], "{d}:", .{lnum}) catch "";
                        pos += p.len;
                    }
                    const remain = @min(line.len, obuf.len - pos - 1);
                    @memcpy(obuf[pos..][0..remain], line[0..remain]);
                    pos += remain;
                    obuf[pos] = '\n';
                    core.writeAll(1, obuf[0 .. pos + 1]);
                }
            }
        }
    }

    if (do_count and matched > 0) {
        var cbuf: [128]u8 = undefined;
        const s = if (name) |n|
            std.fmt.bufPrint(&cbuf, "{s}:{d}\n", .{ n, matched }) catch ""
        else
            std.fmt.bufPrint(&cbuf, "{d}\n", .{matched}) catch "";
        if (s.len > 0) core.writeAll(1, s);
    }

    return matched;
}
