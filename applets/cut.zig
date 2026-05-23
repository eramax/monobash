const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cut", .main = main };

const FieldRange = struct {
    start: usize,
    end: usize,
};

pub fn main(args: [][]const u8) u8 {
    var delim: u8 = '\t';
    var fields: ?[]const u8 = null;
    var char_mode = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "-d")) {
            if (arg.len > 2) {
                delim = arg[2];
            } else {
                i += 1;
                if (i >= args.len) return core.die(1, "cut: option requires an argument: -d\n", .{});
                delim = args[i][0];
            }
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-f")) {
            if (arg.len > 2) {
                fields = arg[2..];
            } else {
                i += 1;
                if (i >= args.len) return core.die(1, "cut: option requires an argument: -f\n", .{});
                fields = args[i];
            }
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-c")) {
            if (arg.len > 2) {
                fields = arg[2..];
                char_mode = true;
            } else {
                i += 1;
                if (i >= args.len) return core.die(1, "cut: option requires an argument: -c\n", .{});
                fields = args[i];
                char_mode = true;
            }
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| {
            switch (flag) {
                'd' => {},
                'f' => {},
                'c' => char_mode = true,
                else => return core.die(1, "cut: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const ranges = if (fields) |f| parseRanges(f) else return core.die(1, "cut: missing -f or -c\n", .{});

    const files = args[i..];
    var exit_code: u8 = 0;

    const alloc = std.heap.page_allocator;

    if (files.len == 0) {
        processFd(0, delim, ranges, char_mode, alloc);
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("cut: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("cut: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);
        processFd(fd, delim, ranges, char_mode, alloc);
    }

    return exit_code;
}

fn parseRanges(s: []const u8) [16]FieldRange {
    var ranges: [16]FieldRange = undefined;
    var count: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const start = i;
        while (i < s.len and s[i] != ',') i += 1;
        const part = s[start..i];
        if (part.len > 0) {
            const dash_pos = std.mem.indexOfScalar(u8, part, '-');
            if (dash_pos) |dp| {
                const a = if (dp > 0) std.fmt.parseUnsigned(usize, part[0..dp], 10) catch 1 else 1;
                const b = if (dp + 1 < part.len) std.fmt.parseUnsigned(usize, part[dp + 1 ..], 10) catch std.math.maxInt(usize) else std.math.maxInt(usize);
                ranges[count] = .{ .start = a, .end = b };
            } else {
                const v = std.fmt.parseUnsigned(usize, part, 10) catch 1;
                ranges[count] = .{ .start = v, .end = v };
            }
            count += 1;
        }
        if (i < s.len) i += 1;
    }
    ranges[count] = .{ .start = 0, .end = 0 };
    return ranges;
}

fn processFd(fd: c_int, delim: u8, ranges: [16]FieldRange, char_mode: bool, alloc: std.mem.Allocator) void {
    const data = core.readAll(alloc, fd, 1024 * 1024) catch return;
    defer alloc.free(data);

    var line_start: usize = 0;
    for (data, 0..) |ch, pos| {
        if (ch == '\n') {
            const line = data[line_start..pos];
            processLine(line, delim, ranges, char_mode);
            core.writeAll(1, "\n");
            line_start = pos + 1;
        }
    }
    if (line_start < data.len) {
        processLine(data[line_start..], delim, ranges, char_mode);
        core.writeAll(1, "\n");
    }
}

fn processLine(line: []const u8, delim: u8, ranges: [16]FieldRange, char_mode: bool) void {
    if (char_mode) {
        var first = true;
        var ri: usize = 0;
        while (ranges[ri].start != 0) : (ri += 1) {
            const r = ranges[ri];
            const s = if (r.start > 0) r.start - 1 else 0;
            const e = @min(r.end, line.len);
            if (s < line.len) {
                if (!first) core.writeAll(1, ",");
                core.writeAll(1, line[s..e]);
                first = false;
            }
        }
        return;
    }

    var field_starts: [256]usize = undefined;
    var field_count: usize = 0;
    var fstart: usize = 0;

    for (line, 0..) |ch, pos| {
        if (ch == delim) {
            field_starts[field_count] = fstart;
            field_count += 1;
            fstart = pos + 1;
            if (field_count >= field_starts.len) break;
        }
    }
    if (field_count < field_starts.len) {
        field_starts[field_count] = fstart;
        field_count += 1;
    }

    var first = true;
    var ri: usize = 0;
    while (ranges[ri].start != 0) : (ri += 1) {
        const r = ranges[ri];
        const fs = if (r.start > 0) r.start - 1 else 0;
        const fe = if (r.end > field_count) field_count else r.end;
        var fi = fs;
        while (fi < fe and fi < field_count) : (fi += 1) {
            if (!first) core.writeAll(1, &[_]u8{delim});
            const fstart_pos = field_starts[fi];
            const fend_pos = if (fi + 1 < field_count) field_starts[fi + 1] - 1 else line.len;
            core.writeAll(1, line[fstart_pos..fend_pos]);
            first = false;
        }
    }
}
