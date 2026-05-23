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
    var suppress = false;
    var output_delim: u8 = 0;
    var regex_mode = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (args[i].len == 1) break;
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
        if (std.mem.startsWith(u8, arg, "-c") or std.mem.startsWith(u8, arg, "-b")) {
            if (arg.len > 2) {
                fields = arg[2..];
                char_mode = true;
            } else {
                i += 1;
                if (i >= args.len) return core.die(1, "cut: option requires an argument\n", .{});
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
                'b', 'c' => char_mode = true,
                's' => suppress = true,
                'n' => {},
                'D' => {
                    if (output_delim == 0) output_delim = ' ';
                },
                'F' => regex_mode = true,
                else => return core.die(1, "cut: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (fields == null and regex_mode and i < args.len) {
        fields = args[i];
        i += 1;
    }

    const ranges = if (fields) |f| parseRanges(f) else return core.die(1, "cut: missing -f or -c\n", .{});

    const files = args[i..];
    var exit_code: u8 = 0;

    const alloc = std.heap.page_allocator;

    if (files.len == 0) {
        processFd(0, delim, ranges, char_mode, suppress, regex_mode, output_delim, alloc);
        return 0;
    }

    for (files) |f| {
        if (std.mem.eql(u8, f, "-")) {
            processFd(0, delim, ranges, char_mode, suppress, regex_mode, output_delim, alloc);
            continue;
        }
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
        processFd(fd, delim, ranges, char_mode, suppress, regex_mode, output_delim, alloc);
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
                if (a > b) return errorRange();
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

fn errorRange() [16]FieldRange {
    core.eprint("cut: invalid range\n", .{});
    std.process.exit(1);
}

fn processFd(fd: c_int, delim: u8, ranges: [16]FieldRange, char_mode: bool, suppress: bool, regex_mode: bool, output_delim: u8, alloc: std.mem.Allocator) void {
    const data = core.readAll(alloc, fd, 1024 * 1024) catch return;
    defer alloc.free(data);

    var line_start: usize = 0;
    for (data, 0..) |ch, pos| {
        if (ch == '\n') {
            const line = data[line_start..pos];
            processLine(line, delim, ranges, char_mode, suppress, regex_mode, output_delim);
            line_start = pos + 1;
        }
    }
    if (line_start < data.len) {
        processLine(data[line_start..], delim, ranges, char_mode, suppress, regex_mode, output_delim);
    }
}

fn processLine(line: []const u8, delim: u8, ranges: [16]FieldRange, char_mode: bool, suppress: bool, regex_mode: bool, output_delim: u8) void {
    if (char_mode) {
        for (1..line.len + 1) |pos| {
            var in_range = false;
            var ri: usize = 0;
            while (ranges[ri].start != 0) : (ri += 1) {
                if (pos >= ranges[ri].start and pos <= ranges[ri].end) {
                    in_range = true;
                    break;
                }
            }
            if (in_range) {
                core.writeAll(1, line[pos - 1 .. pos]);
            }
        }
        core.writeAll(1, "\n");
        return;
    }

    var field_starts: [256]usize = undefined;
    var field_ends: [256]usize = undefined;
    var field_count: usize = 0;

    if (regex_mode) {
        var pos: usize = 0;
        while (pos < line.len) {
            while (pos < line.len and (line[pos] == ' ' or line[pos] == '\t')) : (pos += 1) {}
            if (pos >= line.len) break;
            field_starts[field_count] = pos;
            while (pos < line.len and line[pos] != ' ' and line[pos] != '\t') : (pos += 1) {}
            field_ends[field_count] = pos;
            field_count += 1;
        }
    } else {
        var fstart: usize = 0;
        for (line, 0..) |ch, pos| {
            if (ch == delim) {
                field_starts[field_count] = fstart;
                field_ends[field_count] = pos;
                field_count += 1;
                fstart = pos + 1;
                if (field_count >= field_starts.len) break;
            }
        }
        if (field_count < field_starts.len) {
            field_starts[field_count] = fstart;
            field_ends[field_count] = line.len;
            field_count += 1;
        }

        if (field_count <= 1 and fstart == 0) {
            if (!suppress) {
                core.writeAll(1, line);
                core.writeAll(1, "\n");
            }
            return;
        }
    }

    var first = true;
    var ri: usize = 0;
    while (ranges[ri].start != 0) : (ri += 1) {
        const r = ranges[ri];
        const fs = if (r.start > 0) r.start - 1 else 0;
        const fe = if (r.end > field_count) field_count else r.end;
        var fi = fs;
        while (fi < fe and fi < field_count) : (fi += 1) {
            if (!first) {
                if (output_delim != 0) {
                    core.writeAll(1, &[_]u8{output_delim});
                } else {
                    core.writeAll(1, &[_]u8{delim});
                }
            }
            core.writeAll(1, line[field_starts[fi]..field_ends[fi]]);
            first = false;
        }
    }
    core.writeAll(1, "\n");
}
