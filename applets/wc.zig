const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "wc", .main = main };

pub fn main(args: [][]const u8) u8 {
    var count_lines = false;
    var count_words = false;
    var count_chars = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'l' => count_lines = true,
                'w' => count_words = true,
                'c' => count_chars = true,
                else => return core.die(1, "wc: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (!count_lines and !count_words and !count_chars) {
        count_lines = true;
        count_words = true;
        count_chars = true;
    }

    const alloc = std.heap.page_allocator;
    var total_lines: usize = 0;
    var total_words: usize = 0;
    var total_chars: usize = 0;
    var file_count: usize = 0;
    var exit_code: u8 = 0;

    const files = args[i..];

    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
        defer alloc.free(data);
        const l = countLines(data);
        const w = countWords(data);
        const c = data.len;
        printCounts(l, w, c, count_lines, count_words, count_chars, "");
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("wc: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("wc: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        const data = core.readAll(alloc, fd, 1024 * 1024) catch {
            exit_code = 1;
            continue;
        };
        defer alloc.free(data);

        const l = countLines(data);
        const w = countWords(data);
        const c = data.len;
        total_lines += l;
        total_words += w;
        total_chars += c;
        file_count += 1;
        printCounts(l, w, c, count_lines, count_words, count_chars, f);
    }

    if (file_count > 1) {
        printCounts(total_lines, total_words, total_chars, count_lines, count_words, count_chars, "total");
    }

    return exit_code;
}

fn countLines(data: []const u8) usize {
    var n: usize = 0;
    for (data) |ch| {
        if (ch == '\n') n += 1;
    }
    return n;
}

fn countWords(data: []const u8) usize {
    var n: usize = 0;
    var in_word = false;
    for (data) |ch| {
        const is_space = ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
        if (is_space) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            n += 1;
        }
    }
    return n;
}

fn printCounts(lines: usize, words: usize, chars: usize, show_l: bool, show_w: bool, show_c: bool, name: []const u8) void {
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    if (show_l) {
        const s = std.fmt.bufPrint(buf[pos..], "{d:>7} ", .{lines}) catch "";
        pos += s.len;
    }
    if (show_w) {
        const s = std.fmt.bufPrint(buf[pos..], "{d:>7} ", .{words}) catch "";
        pos += s.len;
    }
    if (show_c) {
        const s = std.fmt.bufPrint(buf[pos..], "{d:>7} ", .{chars}) catch "";
        pos += s.len;
    }
    if (name.len > 0) {
        const s = std.fmt.bufPrint(buf[pos..], "{s}\n", .{name}) catch "";
        pos += s.len;
    } else {
        buf[pos] = '\n';
        pos += 1;
    }
    core.writeAll(1, buf[0..pos]);
}
