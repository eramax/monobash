const std = @import("std");
const core = @import("core.zig");
const mvzr = @import("mvzr");

pub const meta = core.AppletMeta{ .name = "grep", .main = main };

fn lowerCase(s: []const u8, buf: []u8) []const u8 {
    const n = @min(s.len, buf.len);
    for (s[0..n], 0..) |c, i| buf[i] = switch (c) { 'A'...'Z' => c + 32, else => c };
    return buf[0..n];
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var ci = false;
    var invert = false;
    var do_count = false;
    var do_lnum = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| switch (flag) {
            'i' => ci = true, 'v' => invert = true,
            'c' => do_count = true, 'n' => do_lnum = true,
            else => return core.die(2, "grep: unknown flag '-{c}'\n", .{flag}),
        };
        i += 1;
    }
    if (i >= args.len) return core.die(2, "grep: missing pattern\n", .{});
    const pattern = args[i];
    i += 1;
    const files = args[i..];

    var pat_buf: [4096]u8 = undefined;
    const pat = if (ci) lowerCase(pattern, &pat_buf) else pattern;
    const re = mvzr.Regex.compile(pat) orelse
        return core.die(2, "grep: invalid pattern\n", .{});

    var matched: usize = 0;
    var had_err = false;

    if (files.len == 0) {
        matched = grepFile("", 0, &re, invert, do_count, do_lnum, false, ci);
    } else for (files) |f| {
        const fd = core.openReadName(f) orelse {
            core.eprint("grep: {s}: No such file or directory\n", .{f});
            had_err = true;
            continue;
        };
        matched += grepFile(f, fd, &re, invert, do_count, do_lnum, files.len > 1, ci);
        _ = core.c.close(fd);
    }

    return if (matched > 0) 0 else if (had_err) 2 else 1;
}

fn grepFile(name: []const u8, fd: c_int, re: *const mvzr.Regex, invert: bool, do_count: bool, do_lnum: bool, show_name: bool, ci: bool) usize {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return 0;
    defer std.heap.page_allocator.free(data);

    var lnum: usize = 0;
    var matched: usize = 0;
    var start: usize = 0;
    var out: [65536]u8 = undefined;
    var low: [65536]u8 = undefined;

    while (start < data.len) {
        const end = if (std.mem.indexOfScalar(u8, data[start..], '\n')) |nl| start + nl else data.len;
        lnum += 1;
        const line = data[start..end];
        const hay = if (ci) lowerCase(line, &low) else line;
        const is_match = re.match(hay) != null;
        const show = if (invert) !is_match else is_match;
        if (show) {
            matched += 1;
            if (!do_count) {
                var pos: usize = 0;
                if (show_name) {
                    const p = std.fmt.bufPrint(out[pos..], "{s}:", .{name}) catch "";
                    pos += p.len;
                }
                if (do_lnum) {
                    const p = std.fmt.bufPrint(out[pos..], "{d}:", .{lnum}) catch "";
                    pos += p.len;
                }
                const rem = @min(line.len, out.len - pos - 1);
                @memcpy(out[pos..][0..rem], line[0..rem]);
                pos += rem;
                out[pos] = '\n';
                core.writeAll(1, out[0..pos+1]);
            }
        }
        start = end + 1;
    }
    if (do_count and matched > 0) {
        const s = if (show_name)
            std.fmt.bufPrint(&out, "{s}:{d}\n", .{name, matched}) catch ""
        else
            std.fmt.bufPrint(&out, "{d}\n", .{matched}) catch "";
        if (s.len > 0) core.writeAll(1, s);
    }
    return matched;
}
