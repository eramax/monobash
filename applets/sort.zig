const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sort", .main = main };

fn parseNum(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    const trimmed = std.mem.trim(u8, s, &[_]u8{' ', '\t'});
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

pub fn main(args: [][]const u8) u8 {
    var reverse = false;
    var numeric = false;
    var unique = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'r' => reverse = true,
                'n' => numeric = true,
                'u' => unique = true,
                'k' => {},
                else => return core.die(2, "sort: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    const alloc = std.heap.page_allocator;
    var lines: std.ArrayListAligned([]const u8, null) = .empty;
    defer lines.deinit(alloc);

    if (files.len == 0) {
        var reader = core.LineReader.init(0);
        while (reader.next()) |line| {
            const dup = alloc.dupe(u8, line) catch return 1;
            lines.append(alloc, dup) catch return 1;
        }
    } else for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("sort: {s}: path too long\n", .{f});
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("sort: {s}: No such file or directory\n", .{f});
            continue;
        }
        defer _ = core.c.close(fd);
        var reader = core.LineReader.init(fd);
        while (reader.next()) |line| {
            const dup = alloc.dupe(u8, line) catch return 1;
            lines.append(alloc, dup) catch return 1;
        }
    }

    if (numeric) {
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                const na = parseNum(a) orelse 0;
                const nb = parseNum(b) orelse 0;
                return na < nb;
            }
        }.less);
    } else {
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
    }

    var out: [8192]u8 = undefined;
    var prev: ?[]const u8 = null;
    var j: usize = 0;
    while (j < lines.items.len) : (j += 1) {
        const idx = if (reverse) lines.items.len - 1 - j else j;
        const line = lines.items[idx];
        if (unique) {
            if (prev) |p| {
                if (std.mem.eql(u8, p, line)) continue;
            }
            prev = line;
        }
        const n = @min(line.len, out.len - 1);
        @memcpy(out[0..n], line[0..n]);
        out[n] = '\n';
        core.writeAll(1, out[0 .. n + 1]);
    }

    return 0;
}
