const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "grep", .main = main };

const MatchState = struct {
    regex: ?*core.c.regex_t = null,
    fixed: bool = false,
    pattern: []const u8 = "",
    reg_buf: []u8 = &.{},
};

const GrepOpts = struct {
    ci: bool = false,
    invert: bool = false,
    do_count: bool = false,
    do_lnum: bool = false,
    quiet: bool = false,
    fixed: bool = false,
    whole_line: bool = false,
    word_match: bool = false,
    only_match: bool = false,
    ext_regex: bool = false,
    recursive: bool = false,
    silent: bool = false,
    files_with_matches: bool = false,
    files_without_matches: bool = false,
    max_count: ?usize = null,
    ctx_after: usize = 0,
    ctx_before: usize = 0,
    ctx_around: usize = 0,
    patterns: std.ArrayListUnmanaged([]const u8) = .{ .items = &.{}, .capacity = 0 },
    pattern_file: ?[]const u8 = null,
};

fn addPattern(list: *std.ArrayListUnmanaged([]const u8), pat: []const u8) void {
    // Split on newlines to support multi-line patterns
    var start: usize = 0;
    while (start < pat.len) {
        const end = if (std.mem.indexOfScalar(u8, pat[start..], '\n')) |nl| start + nl else pat.len;
        const p = pat[start..end];
        if (p.len > 0 or (p.len == 0 and end == pat.len)) {
            const dup = std.heap.page_allocator.dupe(u8, p) catch return;
            list.append(std.heap.page_allocator, dup) catch return;
        }
        if (end >= pat.len) break;
        start = end + 1;
    }
}

pub fn main(args: [][]const u8) u8 {
    var opts = GrepOpts{};
    var i: usize = 1;
    var had_ddash = false;

    while (i < args.len) {
        if (!had_ddash and std.mem.eql(u8, args[i], "--")) {
            had_ddash = true;
            i += 1;
            break;
        }
        if (!had_ddash and args[i].len > 0 and args[i][0] == '-') {
            const arg = args[i];
            if (arg.len == 1) {
                // bare "-" is stdin
                break;
            }
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                switch (arg[j]) {
                    'i' => opts.ci = true,
                    'v' => opts.invert = true,
                    'c' => opts.do_count = true,
                    'n' => opts.do_lnum = true,
                    'q' => opts.quiet = true,
                    'F' => opts.fixed = true,
                    'x' => opts.whole_line = true,
                    'o' => opts.only_match = true,
                    'E' => opts.ext_regex = true,
                    'w' => opts.word_match = true,
                    'r', 'R' => opts.recursive = true,
                    's' => opts.silent = true,
                    'l' => opts.files_with_matches = true,
                    'L' => opts.files_without_matches = true,
                    'e' => {
                        if (j + 1 < arg.len) {
                            addPattern(&opts.patterns, arg[j + 1 ..]);
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'e'\n", .{});
                            addPattern(&opts.patterns, args[i]);
                        }
                    },
                    'f' => {
                        if (j + 1 < arg.len) {
                            opts.pattern_file = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'f'\n", .{});
                            opts.pattern_file = args[i];
                        }
                    },
                    'm' => {
                        if (j + 1 < arg.len) {
                            opts.max_count = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(2, "grep: invalid max count\n", .{});
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'm'\n", .{});
                            opts.max_count = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(2, "grep: invalid max count\n", .{});
                        }
                    },
                    'A' => {
                        if (j + 1 < arg.len) {
                            opts.ctx_after = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'A'\n", .{});
                            opts.ctx_after = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                        }
                    },
                    'B' => {
                        if (j + 1 < arg.len) {
                            opts.ctx_before = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'B'\n", .{});
                            opts.ctx_before = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                        }
                    },
                    'C' => {
                        if (j + 1 < arg.len) {
                            opts.ctx_around = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "grep: option requires an argument -- 'C'\n", .{});
                            opts.ctx_around = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(2, "grep: invalid context length\n", .{});
                        }
                    },
                    else => return core.die(2, "grep: unknown flag '-{c}'\n", .{arg[j]}),
                }
            }
            i += 1;
        } else break;
    }

    if (opts.ctx_around > 0) {
        opts.ctx_after = opts.ctx_around;
        opts.ctx_before = opts.ctx_around;
    }

    const had_pat_spec = opts.pattern_file != null or opts.patterns.items.len > 0;

    if (opts.pattern_file) |pf| {
        readPatternFile(pf, &opts.patterns);
    }

    if (opts.patterns.items.len == 0 and !had_pat_spec) {
        if (i >= args.len) return core.die(2, "grep: missing pattern\n", .{});
        addPattern(&opts.patterns, args[i]);
        i += 1;
    }

    const files = args[i..];
    const alloc = std.heap.page_allocator;

    var match_data = std.ArrayListUnmanaged(MatchState){ .items = &.{}, .capacity = 0 };
    defer {
        for (match_data.items) |*m| {
            if (m.regex) |r| core.c.regfree(r);
            if (m.reg_buf.len > 0) alloc.free(m.reg_buf);
        }
        match_data.deinit(alloc);
    }

    for (opts.patterns.items) |pat| {
        var ms = MatchState{
            .pattern = pat,
            .fixed = opts.fixed,
        };
        if (!ms.fixed and pat.len > 0) {
            var pat_buf: [4096:0]u8 = undefined;
            if (pat.len >= pat_buf.len) return core.die(2, "grep: pattern too long\n", .{});
            @memcpy(pat_buf[0..pat.len], pat);
            pat_buf[pat.len] = 0;
            var cflags: c_int = core.c.REG_EXTENDED;
            if (opts.ci) cflags |= core.c.REG_ICASE;
            const reg_size: usize = 4096;
            const reg_mem = alloc.alloc(u8, reg_size) catch return 2;
            const regex: *core.c.regex_t = @ptrCast(@alignCast(reg_mem.ptr));
            if (core.c.regcomp(regex, &pat_buf, cflags) != 0) {
                alloc.free(reg_mem);
                return core.die(2, "grep: invalid pattern\n", .{});
            }
            ms.regex = regex;
            ms.reg_buf = reg_mem;
        }
        match_data.append(alloc, ms) catch return 2;
    }

    var total_matched: usize = 0;
    var printed_file: bool = false;
    var had_err = false;

    if (files.len == 0) {
        const m = grepFile("", 0, &opts, &match_data, false, &had_err);
        if (opts.files_without_matches and m == 0) { core.writeAll(1, "(standard input)\n"); printed_file = true; }
        else total_matched += m;
    } else for (files) |f| {
        if (opts.recursive) {
            total_matched += grepRecursive(f, &opts, &match_data, &had_err);
        } else if (std.mem.eql(u8, f, "-")) {
            const m = grepFile("(standard input)", 0, &opts, &match_data, files.len > 1, &had_err);
            if (opts.files_without_matches and m == 0) { core.writeAll(1, "(standard input)\n"); printed_file = true; }
            else if (opts.files_with_matches and m > 0) { printed_file = true; }
            else total_matched += m;
        } else {
            const fd = core.openReadName(f) orelse {
                if (!opts.silent)
                    core.eprint("grep: {s}: No such file or directory\n", .{f});
                had_err = true;
                continue;
            };
            const m = grepFile(f, fd, &opts, &match_data, files.len > 1, &had_err);
            _ = core.c.close(fd);
            if (opts.files_with_matches and m > 0) { core.writeAll(1, f); core.writeAll(1, "\n"); printed_file = true; }
            else if (opts.files_without_matches and m == 0) { core.writeAll(1, f); core.writeAll(1, "\n"); printed_file = true; }
            else total_matched += m;
        }
    }

    if (printed_file) return 0;
    if (opts.files_without_matches) return 1;
    if (opts.quiet and total_matched > 0) return 0;
    if (had_err) return 2;
    if (total_matched > 0) return 0;
    return 1;
}

fn readPatternFile(path: []const u8, patterns: *std.ArrayListUnmanaged([]const u8)) void {
    if (std.mem.eql(u8, path, "-")) {
        var reader = core.LineReader.init(0);
        while (reader.next()) |line| {
            const dup = std.heap.page_allocator.dupe(u8, line) catch return;
            patterns.append(std.heap.page_allocator, dup) catch return;
        }
        return;
    }
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const fd = core.c.open(&buf, core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        const dup = std.heap.page_allocator.dupe(u8, line) catch return;
        patterns.append(std.heap.page_allocator, dup) catch return;
    }
}

fn matchLine(line: []const u8, opts: *const GrepOpts, match_data: *const std.ArrayListUnmanaged(MatchState)) bool {
    if (match_data.items.len == 0) return false;
    for (match_data.items) |ms| {
        if (ms.fixed) {
            var match = false;
            const search_line = if (opts.ci) lowerCaseTmp(line) else line;
            const search_pat = if (opts.ci) lowerCaseTmp(ms.pattern) else ms.pattern;
            if (opts.word_match) {
                match = isWordMatch(line, ms.pattern, opts.ci);
            } else if (opts.whole_line) {
                match = std.mem.eql(u8, search_line, search_pat);
            } else {
                match = std.mem.indexOf(u8, search_line, search_pat) != null;
            }
            if (match) return true;
        } else if (ms.regex) |re| {
            var zline: [65537:0]u8 = undefined;
            const n = @min(line.len, zline.len - 1);
            @memcpy(zline[0..n], line[0..n]);
            zline[n] = 0;
            if (opts.whole_line) {
                var matches: [1]core.c.regmatch_t = undefined;
                if (core.c.regexec(re, &zline, 1, &matches, 0) != 0) continue;
                if (matches[0].rm_so != 0 or @as(usize, @intCast(matches[0].rm_eo)) != line.len) continue;
            } else if (opts.word_match) {
                var offset: usize = 0;
                var found = false;
                while (offset <= line.len) {
                    var matches: [1]core.c.regmatch_t = undefined;
                    matches[0].rm_so = @intCast(offset);
                    matches[0].rm_eo = @intCast(line.len);
                    const rc = core.c.regexec(re, &zline, 1, &matches, core.c.REG_STARTEND);
                    if (rc != 0) break;
                    const so = @as(usize, @intCast(matches[0].rm_so));
                    const eo = @as(usize, @intCast(matches[0].rm_eo));
                    if (so == eo) { offset += 1; continue; }
                    if ((so == 0 or !isWordChar(line[so - 1])) and (eo >= line.len or !isWordChar(line[eo]))) {
                        found = true;
                        break;
                    }
                    offset = eo;
                }
                if (!found) continue;
            } else {
                if (core.c.regexec(re, &zline, 0, null, 0) != 0) continue;
            }
            return true;
        }
    }
    return false;
}

fn isWordMatch(line: []const u8, pattern: []const u8, ci: bool) bool {
    if (pattern.len == 0) return false;
    var start: usize = 0;
    while (start <= line.len) {
        if (start > 0 and isWordChar(line[start - 1])) {
            start += 1;
            continue;
        }
        if (start + pattern.len > line.len) break;
        const slice = line[start..start + pattern.len];
        const match = if (ci) blk: {
            var all = true;
            for (slice, pattern) |a, b| { if (std.ascii.toLower(a) != std.ascii.toLower(b)) { all = false; break; } }
            break :blk all;
        } else std.mem.eql(u8, slice, pattern);
        if (match) {
            if (start + pattern.len < line.len and isWordChar(line[start + pattern.len])) {
                start += 1;
                continue;
            }
            return true;
        }
        start += 1;
    }
    return false;
}

fn isWordChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn isWordBoundary(line: []const u8, m: core.c.regmatch_t) bool {
    const so = @as(usize, @intCast(m.rm_so));
    const eo = @as(usize, @intCast(m.rm_eo));
    if (so > 0 and isWordChar(line[so - 1])) return false;
    if (eo < line.len and isWordChar(line[eo])) return false;
    return true;
}

fn lowerCaseTmp(s: []const u8) []const u8 {
    // Small in-place buffer for case-insensitive comparison
    var buf: [4096]u8 = undefined;
    const n = @min(s.len, buf.len);
    for (s[0..n], 0..) |c, j| buf[j] = switch (c) { 'A'...'Z' => c + 32, else => c };
    return buf[0..n];
}

fn grepFile(name: []const u8, fd: c_int, opts: *const GrepOpts, match_data: *const std.ArrayListUnmanaged(MatchState), show_name: bool, _: *bool) usize {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return 0;
    defer std.heap.page_allocator.free(data);

    const alloc = std.heap.page_allocator;
    var lines = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer lines.deinit(alloc);
    var lnum: usize = 0;
    var start: usize = 0;
    while (start < data.len) {
        const end = if (std.mem.indexOfScalar(u8, data[start..], '\n')) |nl| start + nl else data.len;
        lnum += 1;
        const line = data[start..end];
        const dup = alloc.dupe(u8, line) catch return 0;
        lines.append(alloc, dup) catch return 0;
        start = end + 1;
    }
    const total_lines = lnum;

    var out: [65536]u8 = undefined;
    var matched: usize = 0;
    var last_match_line: i64 = -1;
    var ctx_buf = std.ArrayListUnmanaged(struct { line: []const u8, lnum: usize }){ .items = &.{}, .capacity = 0 };
    defer ctx_buf.deinit(alloc);

    var li: usize = 0;
    while (li < total_lines) : (li += 1) {
        const line = lines.items[li];
        const is_match = matchLine(line, opts, match_data);
        const show = if (opts.invert) !is_match else is_match;

        if (show) {
            matched += 1;
            if (opts.quiet) return 1;
            if (opts.files_with_matches) return 1;
            if (opts.max_count) |mc| if (matched > mc) break;

            if (!opts.do_count and !opts.files_with_matches and !opts.files_without_matches) {
                var pos: usize = 0;

                if (last_match_line >= 0 and opts.ctx_before > 0) {
                    const gap = @as(usize, @intCast(li - @as(u64, @intCast(last_match_line))));
                    if (gap > opts.ctx_before + 1) {
                        out[pos] = '-';
                        out[pos + 1] = '-';
                        pos += 2;
                        if (show_name) { out[pos] = '\n'; pos += 1; }
                        else { out[pos] = '\n'; pos += 1; }
                    }
                }

                if (opts.ctx_before > 0 and last_match_line >= 0) {
                    const gap = @as(usize, @intCast(li - @as(u64, @intCast(last_match_line))));
                    const last_match_u = @as(usize, @intCast(last_match_line));
                    const ctx_start = if (gap > opts.ctx_before + 1) li - opts.ctx_before else last_match_u + 1;
                    const ctx_end = li;
                    var cl = ctx_start;
                    while (cl < ctx_end) : (cl += 1) {
                        const cline = lines.items[cl];
                        if (show_name) {
                            const p = std.fmt.bufPrint(out[pos..], "{s}:", .{name}) catch "";
                            pos += p.len;
                        }
                        if (opts.do_lnum) {
                            const p = std.fmt.bufPrint(out[pos..], "{d}-", .{cl + 1}) catch "";
                            pos += p.len;
                        }
                        const rem = @min(cline.len, out.len - pos - 1);
                        @memcpy(out[pos..][0..rem], cline[0..rem]);
                        pos += rem;
                        out[pos] = '\n';
                        pos += 1;
                    }
                }

                if (show_name and !std.mem.eql(u8, name, "")) {
                    const p = std.fmt.bufPrint(out[pos..], "{s}:", .{name}) catch "";
                    pos += p.len;
                }
                if (opts.do_lnum) {
                    const p = std.fmt.bufPrint(out[pos..], "{d}:", .{li + 1}) catch "";
                    pos += p.len;
                }

                if (opts.only_match) {
                    _ = emitOnlyMatch(line, opts, match_data, &out, pos);
                } else {
                    const rem = @min(line.len, out.len - pos - 1);
                    @memcpy(out[pos..][0..rem], line[0..rem]);
                    pos += rem;
                    out[pos] = '\n';
                    core.writeAll(1, out[0 .. pos + 1]);
                }
            }

            last_match_line = @as(i64, @intCast(li));
        } else if (opts.ctx_after > 0 and last_match_line >= 0) {
            const dist = @as(usize, @intCast(li - @as(u64, @intCast(last_match_line))));
            if (dist <= opts.ctx_after) {
                var pos: usize = 0;

                if (show_name and !std.mem.eql(u8, name, "")) {
                    const p = std.fmt.bufPrint(out[pos..], "{s}:", .{name}) catch "";
                    pos += p.len;
                }
                if (opts.do_lnum) {
                    const p = std.fmt.bufPrint(out[pos..], "{d}-", .{li + 1}) catch "";
                    pos += p.len;
                }

                const rem = @min(line.len, out.len - pos - 1);
                @memcpy(out[pos..][0..rem], line[0..rem]);
                pos += rem;
                out[pos] = '\n';
                core.writeAll(1, out[0 .. pos + 1]);
            }
        }
    }

    if (opts.do_count and matched > 0) {
        const s = if (show_name)
            std.fmt.bufPrint(&out, "{s}:{d}\n", .{ name, matched }) catch ""
        else
            std.fmt.bufPrint(&out, "{d}\n", .{matched}) catch "";
        if (s.len > 0) core.writeAll(1, s);
    }

    return matched;
}

fn emitOnlyMatch(line: []const u8, opts: *const GrepOpts, match_data: *const std.ArrayListUnmanaged(MatchState), out: []u8, pos: usize) usize {
    var p = pos;
    for (match_data.items) |ms| {
        if (ms.fixed) {
            if (opts.word_match) {
                if (isWordMatch(line, ms.pattern, opts.ci)) {
                    const rem = @min(ms.pattern.len, out.len - p - 1);
                    @memcpy(out[p..][0..rem], ms.pattern[0..rem]);
                    p += rem;
                    out[p] = '\n';
                    p += 1;
                    if (p < out.len) {
                        core.writeAll(1, out[0..p]);
                    }
                    return p;
                }
            } else {
                const search_line = if (opts.ci) lowerCaseTmp(line) else line;
                var si: usize = 0;
                while (si < search_line.len) {
                    const search_pat = if (opts.ci) lowerCaseTmp(ms.pattern) else ms.pattern;
                    if (std.mem.indexOf(u8, search_line[si..], search_pat)) |idx| {
                        const actual = si + idx;
                        const end = actual + ms.pattern.len;
                        const rem = @min(ms.pattern.len, out.len - p - 1);
                        @memcpy(out[p..][0..rem], line[actual..end]);
                        p += rem;
                        out[p] = '\n';
                        p += 1;
                        si = end;
                    } else break;
                }
            }
        } else if (ms.regex) |re| {
            var zline: [65537:0]u8 = undefined;
            const n = @min(line.len, zline.len - 1);
            @memcpy(zline[0..n], line[0..n]);
            zline[n] = 0;
            var offset: usize = 0;
            while (offset <= line.len) {
                var matches: [1]core.c.regmatch_t = undefined;
                matches[0].rm_so = @intCast(offset);
                matches[0].rm_eo = @intCast(line.len);
                const rc = core.c.regexec(re, &zline, 1, &matches, core.c.REG_STARTEND);
                if (rc != 0) break;
                const start = @as(usize, @intCast(matches[0].rm_so));
                const end = @as(usize, @intCast(matches[0].rm_eo));
                if (start == end) {
                    offset += 1;
                    continue;
                }
                const rem2 = @min(end - start, out.len - p - 1);
                @memcpy(out[p..][0..rem2], line[start..end]);
                p += rem2;
                out[p] = '\n';
                p += 1;
                offset = end;
            }
        }
    }
    if (p > pos) {
        core.writeAll(1, out[pos..p]);
    }
    return p;
}

fn grepRecursive(path: []const u8, opts: *const GrepOpts, match_data: *const std.ArrayListUnmanaged(MatchState), had_err: *bool) usize {
    return grepRecursiveInner(path, opts, match_data, had_err, true);
}

fn grepRecursiveInner(path: []const u8, opts: *const GrepOpts, match_data: *const std.ArrayListUnmanaged(MatchState), had_err: *bool, follow_links: bool) usize {
    var total: usize = 0;
    var path_buf: [4096:0]u8 = undefined;
    if (path.len >= path_buf.len) return 0;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    var st: core.c.struct_stat = undefined;
    if (follow_links) {
        if (core.c.stat(path_buf[0..path.len :0].ptr, &st) != 0) return 0;
    } else {
        if (core.c.lstat(path_buf[0..path.len :0].ptr, &st) != 0) return 0;
    }

    if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFLNK and !follow_links) {
        return 0;
    }
    if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
        const dir = core.c.opendir(path_buf[0..path.len :0].ptr);
        if (dir) |d| {
            defer _ = core.c.closedir(d);
            while (true) {
                const entry = core.c.readdir(d) orelse break;
                const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&entry[0].d_name)), 0);
                if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
                var child_buf: [4096]u8 = undefined;
                if (path.len + 1 + name.len >= child_buf.len) continue;
                @memcpy(child_buf[0..path.len], path);
                child_buf[path.len] = '/';
                @memcpy(child_buf[path.len + 1 ..][0..name.len], name);
                const child = child_buf[0 .. path.len + 1 + name.len];
                total += grepRecursiveInner(child, opts, match_data, had_err, false);
                if (opts.files_with_matches and total > 0) return total;
                if (opts.quiet and total > 0) return total;
            }
        }
    } else {
        const fd = core.openReadName(path) orelse {
            if (!opts.silent)
                core.eprint("grep: {s}: No such file or directory\n", .{path});
            had_err.* = true;
            return 0;
        };
        defer _ = core.c.close(fd);
        const matched = grepFile(path, fd, opts, match_data, true, had_err);
        if (opts.files_with_matches and matched > 0) {
            core.writeAll(1, path);
            core.writeAll(1, "\n");
            return 1;
        }
        if (opts.files_without_matches and matched == 0) {
            core.writeAll(1, path);
            core.writeAll(1, "\n");
            return 1;
        }
        total += matched;
    }
    return total;
}
