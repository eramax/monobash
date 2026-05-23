const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "uniq", .main = main };

fn skipFields(line: []const u8, n: usize) usize {
    if (n == 0) return 0;
    var i: usize = 0;
    var fields: usize = 0;
    while (i < line.len and fields < n) {
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
        if (i >= line.len) break;
        while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {}
        fields += 1;
    }
    return i;
}

fn compareKey(line: []const u8, skip_fields: usize, skip_chars: usize, max_chars: usize) []const u8 {
    var start = skipFields(line, skip_fields);
    start = @min(start + skip_chars, line.len);
    const end = if (max_chars > 0) @min(start + max_chars, line.len) else line.len;
    return line[start..end];
}

fn linesEqual(a: []const u8, b: []const u8, case_insensitive: bool, skip_fields: usize, skip_chars: usize, max_chars: usize) bool {
    const ka = compareKey(a, skip_fields, skip_chars, max_chars);
    const kb = compareKey(b, skip_fields, skip_chars, max_chars);
    if (case_insensitive)
        return std.ascii.eqlIgnoreCase(ka, kb);
    return std.mem.eql(u8, ka, kb);
}

fn outputLine(line: []const u8, count: usize, do_count: bool, out_fd: c_int) void {
    var buf: [8192]u8 = undefined;
    if (do_count) {
        const s = std.fmt.bufPrint(&buf, "{d:>7} ", .{count}) catch "";
        core.writeAll(out_fd, s);
        const remain = @min(line.len, buf.len - s.len - 1);
        @memcpy(buf[0..remain], line[0..remain]);
        core.writeAll(out_fd, buf[0..remain]);
        core.writeAll(out_fd, "\n");
    } else {
        const remain = @min(line.len, buf.len - 1);
        @memcpy(buf[0..remain], line[0..remain]);
        buf[remain] = '\n';
        core.writeAll(out_fd, buf[0 .. remain + 1]);
    }
}

pub fn main(args: [][]const u8) u8 {
    var do_count = false;
    var case_insensitive = false;
    var only_duplicates = false;
    var show_unique = false;
    var skip_fields: usize = 0;
    var skip_chars: usize = 0;
    var max_chars: usize = 0;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        if (arg.len > 1 and arg[1] >= '0' and arg[1] <= '9') break;
        if (std.mem.eql(u8, arg, "-")) break;
        var j: usize = 1;
        while (j < arg.len) {
            switch (arg[j]) {
                'c' => do_count = true,
                'i' => case_insensitive = true,
                'd' => only_duplicates = true,
                'u' => show_unique = true,
                'f' => {
                    if (j + 1 < arg.len) {
                        skip_fields = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(1, "uniq: invalid number of fields to skip\n", .{});
                        j = arg.len;
                    } else {
                        i += 1;
                        if (i >= args.len) return core.die(1, "uniq: missing number after -f\n", .{});
                        skip_fields = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "uniq: invalid number of fields to skip\n", .{});
                    }
                },
                's' => {
                    if (j + 1 < arg.len) {
                        skip_chars = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(1, "uniq: invalid number of chars to skip\n", .{});
                        j = arg.len;
                    } else {
                        i += 1;
                        if (i >= args.len) return core.die(1, "uniq: missing number after -s\n", .{});
                        skip_chars = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "uniq: invalid number of chars to skip\n", .{});
                    }
                },
                'w' => {
                    if (j + 1 < arg.len) {
                        max_chars = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(1, "uniq: invalid max chars\n", .{});
                        j = arg.len;
                    } else {
                        i += 1;
                        if (i >= args.len) return core.die(1, "uniq: missing number after -w\n", .{});
                        max_chars = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "uniq: invalid max chars\n", .{});
                    }
                },
                else => return core.die(1, "uniq: unknown flag '{c}'\n", .{arg[j]}),
            }
            j += 1;
        }
        i += 1;
    }

    const files = args[i..];

    var in_fd: c_int = 0;
    var need_close_in = false;
    var out_fd: c_int = 1;
    var need_close_out = false;

    if (files.len >= 1 and !std.mem.eql(u8, files[0], "-")) {
        var fbuf: [4096:0]u8 = undefined;
        if (files[0].len >= fbuf.len) return core.die(1, "uniq: path too long: {s}\n", .{files[0]});
        @memcpy(fbuf[0..files[0].len], files[0]);
        fbuf[files[0].len] = 0;
        const fd2 = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd2 < 0) return core.die(1, "uniq: {s}: No such file or directory\n", .{files[0]});
        in_fd = fd2;
        need_close_in = true;
    }

    if (files.len >= 2 and !std.mem.eql(u8, files[1], "-")) {
        var fbuf: [4096:0]u8 = undefined;
        if (files[1].len >= fbuf.len) return core.die(1, "uniq: path too long: {s}\n", .{files[1]});
        @memcpy(fbuf[0..files[1].len], files[1]);
        fbuf[files[1].len] = 0;
        const fd2 = core.c.open(&fbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(u32, 0o666));
        if (fd2 < 0) return core.die(1, "uniq: {s}: Permission denied\n", .{files[1]});
        out_fd = fd2;
        need_close_out = true;
    }

    defer {
        if (need_close_in) _ = core.c.close(in_fd);
        if (need_close_out) _ = core.c.close(out_fd);
    }

    var reader = core.LineReader.init(in_fd);
    var prev: ?[]const u8 = null;
    var prev_owned: ?[]u8 = null;
    var count: usize = 1;

    while (reader.next()) |line| {
        if (prev) |p| {
            const same = linesEqual(p, line, case_insensitive, skip_fields, skip_chars, max_chars);

            if (same) {
                count += 1;
            } else {
                const show = if (only_duplicates and show_unique) false else if (only_duplicates) count > 1 else if (show_unique) count == 1 else true;
                if (show) {
                    outputLine(p, count, do_count, out_fd);
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
        const show = if (only_duplicates and show_unique) false else if (only_duplicates) count > 1 else if (show_unique) count == 1 else true;
        if (show) {
            outputLine(p, count, do_count, out_fd);
        }
        if (prev_owned) |po| std.heap.page_allocator.free(po);
    }

    return 0;
}
