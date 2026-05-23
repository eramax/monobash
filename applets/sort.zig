const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sort", .main = main };

const KeyDef = struct {
    start_field: usize = 0,
    start_char: usize = 0,
    end_field: usize = 0,
    end_char: usize = 0,
    numeric: bool = false,
    reverse: bool = false,
    month: bool = false,
    human: bool = false,
    version: bool = false,
    ignore_blanks: bool = false,
    has_end: bool = false,
};

const SortOpts = struct {
    reverse: bool = false,
    numeric: bool = false,
    unique: bool = false,
    stable: bool = false,
    null_term: bool = false,
    human: bool = false,
    month: bool = false,
    version: bool = false,
    ignore_blanks: bool = false,
    keys: std.ArrayListUnmanaged(KeyDef) = .{ .items = &.{}, .capacity = 0 },
    field_sep: ?u8 = null,
    output_file: ?[]const u8 = null,
};

pub fn main(args: [][]const u8) u8 {
    var opts = SortOpts{};
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i], "-")) break;
        const arg = args[i];
        if (arg.len == 1) break;
        if (arg[1] == 'k') {
            if (arg.len > 2) {
                parseKey(arg[2..], &opts);
            } else {
                i += 1;
                if (i < args.len) parseKey(args[i], &opts);
            }
            i += 1;
            continue;
        }
        if (arg[1] == 't') {
            if (arg.len > 2) {
                opts.field_sep = arg[2];
            } else {
                i += 1;
                if (i < args.len and args[i].len > 0) opts.field_sep = args[i][0];
            }
            i += 1;
            continue;
        }
        if (arg[1] == 'o') {
            if (arg.len > 2) {
                opts.output_file = arg[2..];
            } else {
                i += 1;
                if (i < args.len) opts.output_file = args[i];
            }
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| switch (flag) {
            'r' => opts.reverse = true,
            'n' => opts.numeric = true,
            'u' => opts.unique = true,
            's' => opts.stable = true,
            'z' => opts.null_term = true,
            'h' => opts.human = true,
            'M' => opts.month = true,
            'V' => opts.version = true,
            'b' => opts.ignore_blanks = true,
            else => return core.die(2, "sort: unknown flag '-{c}'\n", .{flag}),
        };
        i += 1;
    }

    const files = args[i..];
    const alloc = std.heap.page_allocator;
    var lines: std.ArrayListUnmanaged([]const u8) = .empty;
    defer lines.deinit(alloc);

    if (files.len == 0) {
        if (opts.null_term)
            readNullLines(0, &lines)
        else
            readLines(0, &lines);
    } else for (files) |f| {
        if (std.mem.eql(u8, f, "-")) {
            if (opts.null_term)
                readNullLines(0, &lines)
            else
                readLines(0, &lines);
            continue;
        }
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
        if (opts.null_term)
            readNullLines(fd, &lines)
        else
            readLines(fd, &lines);
    }

    if (opts.keys.items.len == 0) {
        opts.keys.append(alloc, KeyDef{
            .numeric = opts.numeric,
            .reverse = opts.reverse,
            .month = opts.month,
            .human = opts.human,
            .version = opts.version,
            .ignore_blanks = opts.ignore_blanks,
        }) catch return 1;
    }

    const SortCtx = struct { opts: SortOpts, stable: bool };
    std.mem.sort([]const u8, lines.items, SortCtx{ .opts = opts, .stable = opts.stable }, struct {
        fn less(ctx: SortCtx, a: []const u8, b: []const u8) bool {
            const cmp = compareLines(a, b, ctx.opts);
            if (cmp == 0 and ctx.stable) return false;
            return if (cmp < 0) true else false;
        }
    }.less);

    if (opts.null_term) {
        var out_buf: [65536]u8 = undefined;
        var prev: ?[]const u8 = null;
        var j: usize = 0;
        while (j < lines.items.len) : (j += 1) {
            const idx = j;
            const line = lines.items[idx];
            if (opts.unique) {
                if (prev) |p| {
                    if (compareKeysOnly(p, line, opts) == 0) continue;
                }
                prev = line;
            }
            const n = @min(line.len, out_buf.len - 1);
            @memcpy(out_buf[0..n], line[0..n]);
            out_buf[n] = 0;
            core.writeAll(1, out_buf[0 .. n + 1]);
        }
    } else {
        var out_buf: [65536]u8 = undefined;
        var prev: ?[]const u8 = null;
        var j: usize = 0;
        while (j < lines.items.len) : (j += 1) {
            const line = lines.items[j];
            if (opts.unique) {
                if (prev) |p| {
                    if (compareKeysOnly(p, line, opts) == 0) continue;
                }
                prev = line;
            }
            const n = @min(line.len, out_buf.len - 2);
            @memcpy(out_buf[0..n], line[0..n]);
            out_buf[n] = '\n';
            if (opts.output_file) |of| {
                _ = of;
            } else {
                core.writeAll(1, out_buf[0 .. n + 1]);
            }
        }
    }

    if (opts.output_file) |of| {
        var fbuf: [4096:0]u8 = undefined;
        if (of.len >= fbuf.len) return core.die(2, "sort: output path too long\n", .{});
        @memcpy(fbuf[0..of.len], of);
        fbuf[of.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, core.c.S_IRUSR | core.c.S_IWUSR | core.c.S_IRGRP | core.c.S_IROTH);
        if (fd < 0) return core.die(2, "sort: cannot write output\n", .{});
        defer _ = core.c.close(fd);
        var prev: ?[]const u8 = null;
        var out_buf: [65536]u8 = undefined;
        var j: usize = 0;
        while (j < lines.items.len) : (j += 1) {
            const line = lines.items[j];
            if (opts.unique) {
                if (prev) |p| {
                    if (compareKeysOnly(p, line, opts) == 0) continue;
                }
                prev = line;
            }
            const n = @min(line.len, out_buf.len - 2);
            @memcpy(out_buf[0..n], line[0..n]);
            out_buf[n] = '\n';
            core.writeAll(fd, out_buf[0 .. n + 1]);
        }
    }

    return 0;
}

fn readLines(fd: c_int, lines: *std.ArrayListUnmanaged([]const u8)) void {
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        const dup = std.heap.page_allocator.dupe(u8, line) catch return;
        lines.append(std.heap.page_allocator, dup) catch return;
    }
}

fn readNullLines(fd: c_int, lines: *std.ArrayListUnmanaged([]const u8)) void {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return;
    defer std.heap.page_allocator.free(data);
    var start: usize = 0;
    while (start < data.len) {
        const end = if (std.mem.indexOfScalar(u8, data[start..], 0)) |n| start + n else data.len;
        const line = data[start..end];
        const dup = std.heap.page_allocator.dupe(u8, line) catch return;
        lines.append(std.heap.page_allocator, dup) catch return;
        start = end + 1;
    }
}

fn parseKey(s: []const u8, opts: *SortOpts) void {
    if (s.len == 0) return;
    var k = KeyDef{};
    var pos: usize = 0;

    // Parse start field
    while (pos < s.len and std.ascii.isDigit(s[pos])) : (pos += 1) {}
    if (pos > 0) {
        k.start_field = std.fmt.parseUnsigned(usize, s[0..pos], 10) catch 0;
    }

    // Parse start character
    if (pos < s.len and s[pos] == '.') {
        pos += 1;
        const cstart = pos;
        while (pos < s.len and std.ascii.isDigit(s[pos])) : (pos += 1) {}
        if (pos > cstart) {
            k.start_char = std.fmt.parseUnsigned(usize, s[cstart..pos], 10) catch 0;
        }
    }

    // Parse end field
    if (pos < s.len and s[pos] == ',') {
        k.has_end = true;
        pos += 1;
        const fstart = pos;
        while (pos < s.len and std.ascii.isDigit(s[pos])) : (pos += 1) {}
        if (pos > fstart) {
            k.end_field = std.fmt.parseUnsigned(usize, s[fstart..pos], 10) catch 0;
        } else {
            k.end_field = k.start_field;
        }

        // Parse end character
        if (pos < s.len and s[pos] == '.') {
            pos += 1;
            const cstart2 = pos;
            while (pos < s.len and std.ascii.isDigit(s[pos])) : (pos += 1) {}
            if (pos > cstart2) {
                k.end_char = std.fmt.parseUnsigned(usize, s[cstart2..pos], 10) catch 0;
            }
        }
    }

    // Parse options
    while (pos < s.len) : (pos += 1) {
        switch (s[pos]) {
            'n' => k.numeric = true,
            'r' => k.reverse = true,
            'h' => k.human = true,
            'M' => k.month = true,
            'V' => k.version = true,
            'b' => k.ignore_blanks = true,
            else => {},
        }
    }

    opts.keys.append(std.heap.page_allocator, k) catch {};
}

fn compareLines(a: []const u8, b: []const u8, opts: SortOpts) i8 {
    for (opts.keys.items) |key| {
        const ka = extractKey(a, key, opts.field_sep);
        const kb = extractKey(b, key, opts.field_sep);
        var cmp = compareKeys(ka, kb, key);
        if (cmp != 0) {
            if (key.reverse) cmp = -cmp;
            return cmp;
        }
    }
    // Fallback: full line comparison (unless stable)
    if (!opts.stable) {
        return compareStrings(a, b);
    }
    return 0;
}

fn compareKeysOnly(a: []const u8, b: []const u8, opts: SortOpts) i8 {
    for (opts.keys.items) |key| {
        const ka = extractKey(a, key, opts.field_sep);
        const kb = extractKey(b, key, opts.field_sep);
        var cmp = compareKeys(ka, kb, key);
        if (cmp != 0) {
            if (key.reverse) cmp = -cmp;
            return cmp;
        }
    }
    return 0;
}

fn extractKey(line: []const u8, key: KeyDef, sep: ?u8) []const u8 {
    if (key.start_field == 0) return line;

    // Split line into fields
    var field_starts: [64]usize = undefined;
    var field_ends: [64]usize = undefined;
    var nfields: usize = 0;

    if (sep) |s| {
        // With explicit separator, each separator creates a field boundary
        var fstart: usize = 0;
        for (line, 0..) |c, i| {
            if (c == s) {
                if (nfields < 64) {
                    field_starts[nfields] = fstart;
                    field_ends[nfields] = i;
                    nfields += 1;
                }
                fstart = i + 1;
            }
        }
        // Last field (after final separator)
        if (nfields < 64) {
            field_starts[nfields] = fstart;
            field_ends[nfields] = line.len;
            nfields += 1;
        }
    } else {
        // Default: whitespace-separated fields
        var i: usize = 0;
        var in_field = false;
        var fstart: usize = 0;
        while (i <= line.len) {
            const at_end = i >= line.len;
            const is_sep = if (at_end) true else line[i] == ' ' or line[i] == '\t';
            if (at_end or is_sep) {
                if (in_field) {
                    if (nfields < 64) {
                        field_starts[nfields] = fstart;
                        field_ends[nfields] = i;
                        nfields += 1;
                    }
                    in_field = false;
                }
            } else {
                if (!in_field) {
                    fstart = i;
                    in_field = true;
                }
            }
            i += 1;
        }
    }

    if (nfields == 0) return line;

    const sf = if (key.start_field <= nfields) key.start_field - 1 else nfields - 1;
    const ef = if (key.has_end) blk: {
        if (key.end_field <= nfields) break :blk key.end_field - 1 else break :blk nfields - 1;
    } else sf;

    var start_byte = field_starts[sf];
    if (key.start_char > 0 and start_byte + key.start_char - 1 <= field_ends[ef]) {
        start_byte = start_byte + key.start_char - 1;
    }

    var end_byte = field_ends[ef];
    if (key.end_char > 0 and field_starts[ef] + key.end_char <= field_ends[ef]) {
        end_byte = field_starts[ef] + key.end_char;
    }

    return line[start_byte..end_byte];
}

fn compareKeys(a: []const u8, b: []const u8, key: KeyDef) i8 {
    if (key.numeric) return compareNumeric(a, b);
    if (key.human) return compareHuman(a, b);
    if (key.month) return compareMonth(a, b);
    if (key.version) return compareVersion(a, b);
    return compareStrings(a, b);
}

fn compareStrings(a: []const u8, b: []const u8) i8 {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |ca, cb| {
        if (ca < cb) return -1;
        if (ca > cb) return 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

fn compareNumeric(a: []const u8, b: []const u8) i8 {
    const trimmed_a = std.mem.trim(u8, a, " \t");
    const trimmed_b = std.mem.trim(u8, b, " \t");
    const na = parseNum(trimmed_a);
    const nb = parseNum(trimmed_b);
    if (na < nb) return -1;
    if (na > nb) return 1;
    return 0;
}

fn parseNum(s: []const u8) i64 {
    if (s.len == 0) return 0;
    var end: usize = 0;
    if (s[end] == '-' or s[end] == '+') end += 1;
    while (end < s.len and s[end] >= '0' and s[end] <= '9') : (end += 1) {}
    if (end == 0 or (end == 1 and (s[0] == '-' or s[0] == '+'))) return 0;
    return std.fmt.parseInt(i64, s[0..end], 10) catch 0;
}

fn compareHuman(a: []const u8, b: []const u8) i8 {
    const va = parseHuman(a);
    const vb = parseHuman(b);
    if (va.scale != vb.scale) {
        if (va.scale < vb.scale) return -1;
        return 1;
    }
    if (va.value < vb.value) return -1;
    if (va.value > vb.value) return 1;
    return 0;
}

const HumanVal = struct { value: f64, scale: i8 };

fn parseHuman(s: []const u8) HumanVal {
    const trimmed = std.mem.trim(u8, s, " \t");
    if (trimmed.len == 0) return .{ .value = 0, .scale = -1 };
    // Parse strtod-like: find the first number
    var end: usize = 0;
    if (end < trimmed.len and (trimmed[end] == '-' or trimmed[end] == '+')) end += 1;
    while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
    if (end < trimmed.len and trimmed[end] == '.') {
        end += 1;
        while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
    }
    if (end == 0 or (end == 1 and (trimmed[0] == '-' or trimmed[0] == '+'))) return .{ .value = 0, .scale = -1 };
    const num_str = trimmed[0..end];
    const val = std.fmt.parseFloat(f64, num_str) catch return .{ .value = 0, .scale = -1 };
    // Check suffix (must be at end of string, after the number)
    if (end < trimmed.len) {
        const suffix = trimmed[end];
        // Match k=0, m=1, g=2, t=3, p=4, e=5, z=6, y=7
        const scale: i8 = switch (std.ascii.toLower(suffix)) {
            'k' => 0,
            'm' => 1,
            'g' => 2,
            't' => 3,
            'p' => 4,
            'e' => 5,
            'z' => 6,
            'y' => 7,
            else => -1,
        };
        if (scale >= 0) {
            // Only accept uppercase suffixes (except 'k' = index 0)
            if (scale != 0 and suffix >= 'a') return .{ .value = val, .scale = -1 };
            return .{ .value = val, .scale = scale };
        }
    }
    return .{ .value = val, .scale = -1 };
}




fn compareMonth(a: []const u8, b: []const u8) i8 {
    const ma = parseMonth(a);
    const mb = parseMonth(b);
    if (ma < mb) return -1;
    if (ma > mb) return 1;
    return 0;
}

fn parseMonth(s: []const u8) u8 {
    const trimmed = std.mem.trim(u8, s, " \t");
    if (trimmed.len < 3) return 0;
    var buf: [3]u8 = undefined;
    for (trimmed[0..3], 0..) |c, j| buf[j] = std.ascii.toLower(c);
    const m3 = buf;
    if (std.mem.eql(u8, &m3, "jan")) return 1;
    if (std.mem.eql(u8, &m3, "feb")) return 2;
    if (std.mem.eql(u8, &m3, "mar")) return 3;
    if (std.mem.eql(u8, &m3, "apr")) return 4;
    if (std.mem.eql(u8, &m3, "may")) return 5;
    if (std.mem.eql(u8, &m3, "jun")) return 6;
    if (std.mem.eql(u8, &m3, "jul")) return 7;
    if (std.mem.eql(u8, &m3, "aug")) return 8;
    if (std.mem.eql(u8, &m3, "sep")) return 9;
    if (std.mem.eql(u8, &m3, "oct")) return 10;
    if (std.mem.eql(u8, &m3, "nov")) return 11;
    if (std.mem.eql(u8, &m3, "dec")) return 12;
    return 0;
}

fn compareVersion(a: []const u8, b: []const u8) i8 {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len or j < b.len) {
        // Skip non-digit, non-dot prefixes
        while (i < a.len and !std.ascii.isDigit(a[i])) : (i += 1) {}
        while (j < b.len and !std.ascii.isDigit(b[j])) : (j += 1) {}

        // Parse number
        var na: u64 = 0;
        while (i < a.len and std.ascii.isDigit(a[i])) : (i += 1) {
            na = na * 10 + (a[i] - '0');
        }
        var nb: u64 = 0;
        while (j < b.len and std.ascii.isDigit(b[j])) : (j += 1) {
            nb = nb * 10 + (b[j] - '0');
        }
        if (na < nb) return -1;
        if (na > nb) return 1;
    }
    return 0;
}
