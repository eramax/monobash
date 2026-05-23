const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "diff", .main = main };

const Flags = struct {
    unified: bool = false,
    ignore_space: bool = false,
    ignore_blank: bool = false,
    brief: bool = false,
    recursive: bool = false,
    new_file: bool = false,
};

const Edit = struct { tag: enum { keep, del, ins }, text: []u8 };

pub fn main(args: [][]const u8) u8 {
    var fl = Flags{};
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i], "-")) break; // "-" is stdin, not a flag
        for (args[i][1..]) |c| switch (c) {
            'u' => fl.unified = true,
            'b' => fl.ignore_space = true,
            'B' => fl.ignore_blank = true,
            'q' => fl.brief = true,
            'r' => fl.recursive = true,
            'N' => fl.new_file = true,
            'H' => {},
            else => return core.die(2, "diff: unknown flag '-{c}'\n", .{c}),
        };
        i += 1;
    }
    if (i + 2 > args.len) return core.die(2, "diff: missing file arguments\n", .{});
    const f1 = args[i];
    const f2 = args[i + 1];
    if (std.mem.eql(u8, f1, "-") and std.mem.eql(u8, f2, "-")) return 0;
    return diff(&fl, f1, f2, std.heap.page_allocator);
}

fn diff(fl: *const Flags, f1: []const u8, f2: []const u8, a: std.mem.Allocator) u8 {
    const d1 = isDir(f1);
    const d2 = isDir(f2);
    if (d1 and d2) return diffDirs(fl, f1, f2, a);
    if (d1) return diffDirFile(fl, f1, f2, a);
    if (d2) return diffFileDir(fl, f1, f2, a);
    const is_stdin1 = std.mem.eql(u8, f1, "-");
    const is_stdin2 = std.mem.eql(u8, f2, "-");
    if (!is_stdin1 and !isReg(f1) and !isDir(f1)) {
        core.writeAll(2, "diff: ");
        core.writeAll(2, f1);
        core.writeAll(2, " is not a regular file or directory\n");
        return 1;
    }
    if (!is_stdin2 and !isReg(f2) and !isDir(f2)) {
        core.writeAll(2, "diff: ");
        core.writeAll(2, f2);
        core.writeAll(2, " is not a regular file or directory\n");
        return 1;
    }

    var no_eol1 = false;
    var no_eol2 = false;
    const l1 = readLines(f1, a, &no_eol1) orelse return core.die(2, "diff: {s}: No such file or directory\n", .{f1});
    defer freeLines(l1, a);
    const l2 = readLines(f2, a, &no_eol2) orelse return core.die(2, "diff: {s}: No such file or directory\n", .{f2});
    defer freeLines(l2, a);

    if (fl.brief) {
        if (roughEq(fl, l1, l2)) return 0;
        core.writeAll(1, "Files ");
        core.writeAll(1, f1);
        core.writeAll(1, " and ");
        core.writeAll(1, f2);
        core.writeAll(1, " differ\n");
        return 1;
    }

    if (fl.unified) return unifiedDiff(fl, f1, f2, l1, l2, no_eol1, no_eol2);
    return simpleDiff(f1, f2, l1, l2);
}

fn isDir(p: []const u8) bool {
    var buf: [4096:0]u8 = undefined;
    if (p.len >= buf.len) return false;
    @memcpy(buf[0..p.len], p);
    buf[p.len] = 0;
    var st: core.c.struct_stat = undefined;
    if (core.c.stat(buf[0..p.len :0].ptr, &st) != 0) return false;
    return (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR;
}

fn isReg(p: []const u8) bool {
    var buf: [4096:0]u8 = undefined;
    if (p.len >= buf.len) return false;
    @memcpy(buf[0..p.len], p);
    buf[p.len] = 0;
    var st: core.c.struct_stat = undefined;
    if (core.c.stat(buf[0..p.len :0].ptr, &st) != 0) return false;
    return (st.st_mode & core.c.S_IFMT) == core.c.S_IFREG;
}

fn freeLines(l: [][]const u8, a: std.mem.Allocator) void {
    for (l) |s| a.free(s);
    a.free(l);
}

fn freeEdits(e: []Edit, a: std.mem.Allocator) void {
    for (e) |ed| a.free(ed.text);
    a.free(e);
}

fn readLines(name: []const u8, a: std.mem.Allocator, no_eol: *bool) ?[][]const u8 {
    const fd = if (std.mem.eql(u8, name, "-")) 0 else blk: {
        var buf: [4096:0]u8 = undefined;
        if (name.len >= buf.len) return null;
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        const f = core.c.open(buf[0..name.len :0].ptr, core.c.O_RDONLY);
        if (f < 0) return null;
        break :blk f;
    };
    const needs_close = !std.mem.eql(u8, name, "-");
    defer {
        if (needs_close) _ = core.c.close(fd);
    }

    var lines = std.ArrayListAligned([]const u8, null).empty;
    var reader = core.LineReader.init(fd);
    var last_was_newline = true;
    while (reader.nextWithTerminator()) |item| {
        last_was_newline = item.terminated;
        const d = a.dupe(u8, item.line) catch return null;
        lines.append(a, d) catch return null;
    }
    no_eol.* = !last_was_newline and lines.items.len > 0;
    return lines.toOwnedSlice(a) catch return null;
}

fn roughEq(fl: *const Flags, a: [][]const u8, b: [][]const u8) bool {
    var ai: usize = 0;
    var bi: usize = 0;
    while (ai < a.len and bi < b.len) {
        if (fl.ignore_blank and isBlank(a[ai])) { ai += 1; continue; }
        if (fl.ignore_blank and isBlank(b[bi])) { bi += 1; continue; }
        if (!lineEq(fl, a[ai], b[bi])) return false;
        ai += 1;
        bi += 1;
    }
    if (fl.ignore_blank) {
        while (ai < a.len and isBlank(a[ai])) ai += 1;
        while (bi < b.len and isBlank(b[bi])) bi += 1;
    }
    return ai == a.len and bi == b.len;
}

fn collapseSpace(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t");
}

fn lineEq(fl: *const Flags, a: []const u8, b: []const u8) bool {
    if (fl.ignore_space) {
        // Collapse all whitespace sequences to single space
        var abuf: [8192]u8 = undefined;
        var bbuf: [8192]u8 = undefined;
        var ai: usize = 0;
        var bi: usize = 0;
        var in_ws = false;
        for (a) |c| {
            if (c == ' ' or c == '\t') {
                if (!in_ws) { in_ws = true; abuf[ai] = ' '; ai += 1; }
            } else {
                in_ws = false;
                abuf[ai] = c; ai += 1;
            }
        }
        in_ws = false;
        for (b) |c| {
            if (c == ' ' or c == '\t') {
                if (!in_ws) { in_ws = true; bbuf[bi] = ' '; bi += 1; }
            } else {
                in_ws = false;
                bbuf[bi] = c; bi += 1;
            }
        }
        const ac = std.mem.trim(u8, abuf[0..ai], " ");
        const bc = std.mem.trim(u8, bbuf[0..bi], " ");
        return std.mem.eql(u8, ac, bc);
    }
    return std.mem.eql(u8, a, b);
}

fn isBlank(s: []const u8) bool {
    for (s) |c| if (c != ' ' and c != '\t') return false;
    return true;
}

fn simpleDiff(f1: []const u8, f2: []const u8, a: [][]const u8, b: [][]const u8) u8 {
    _ = f1; _ = f2;
    var differed = false;
    var buf: [8192]u8 = undefined;
    const m = @max(a.len, b.len);
    for (0..m) |j| {
        const la = if (j < a.len) a[j] else "";
        const lb = if (j < b.len) b[j] else "";
        if (!std.mem.eql(u8, la, lb)) {
            differed = true;
            const info = std.fmt.bufPrint(&buf, "{d}c{d}\n", .{ j + 1, j + 1 }) catch "";
            core.writeAll(1, info);
            core.writeAll(1, "< "); core.writeAll(1, la); core.writeAll(1, "\n");
            core.writeAll(1, "---\n");
            core.writeAll(1, "> "); core.writeAll(1, lb); core.writeAll(1, "\n");
        }
    }
    return if (differed) 1 else 0;
}

fn LCS(a: [][]const u8, b: [][]const u8, fl: *const Flags, al: std.mem.Allocator) []Edit {
    const m = a.len;
    const n = b.len;
    if (m == 0 and n == 0) {
        return al.alloc(Edit, 0) catch unreachable;
    }
    if (m == 0) {
        var res = al.alloc(Edit, n) catch unreachable;
        for (b, 0..) |l, i| res[i] = .{ .tag = .ins, .text = al.dupe(u8, l) catch unreachable };
        return res;
    }
    if (n == 0) {
        var res = al.alloc(Edit, m) catch unreachable;
        for (a, 0..) |l, i| res[i] = .{ .tag = .del, .text = al.dupe(u8, l) catch unreachable };
        return res;
    }

    var dp = al.alloc([]u32, m + 1) catch unreachable;
    defer al.free(dp);
    for (0..m + 1) |i| {
        dp[i] = al.alloc(u32, n + 1) catch unreachable;
        @memset(dp[i], 0);
    }
    defer for (dp) |row| al.free(row);

    for (1..m + 1) |i| {
        const ai = a[i - 1];
        const dpi = dp[i];
        const dpi_1 = dp[i - 1];
        for (1..n + 1) |j| {
            dpi[j] = if (lineEq(fl, ai, b[j - 1]))
                dpi_1[j - 1] + 1
            else
                @max(dpi_1[j], dpi[j - 1]);
        }
    }

    var edits = std.ArrayListAligned(Edit, null).empty;
    var i: usize = m;
    var j: usize = n;
    while (i > 0 or j > 0) {
        if (i > 0 and j > 0 and lineEq(fl, a[i - 1], b[j - 1])) {
            edits.append(al, .{ .tag = .keep, .text = al.dupe(u8, a[i - 1]) catch unreachable }) catch unreachable;
            i -= 1; j -= 1;
        } else if (j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j])) {
            edits.append(al, .{ .tag = .ins, .text = al.dupe(u8, b[j - 1]) catch unreachable }) catch unreachable;
            j -= 1;
        } else {
            edits.append(al, .{ .tag = .del, .text = al.dupe(u8, a[i - 1]) catch unreachable }) catch unreachable;
            i -= 1;
        }
    }
    std.mem.reverse(Edit, edits.items);
    return edits.toOwnedSlice(al) catch unreachable;
}

fn unifiedDiff(fl: *const Flags, f1: []const u8, f2: []const u8, a: [][]const u8, b: [][]const u8, no_eol1: bool, no_eol2: bool) u8 {
    _ = no_eol1;
    const al = std.heap.page_allocator;

    var aa = std.ArrayListAligned([]const u8, null).empty;
    var bb = std.ArrayListAligned([]const u8, null).empty;

    // For -B: track which lines are blank in originals
    var a_blank: ?[]bool = null;
    var b_blank: ?[]bool = null;
    defer {
        if (a_blank) |ab| al.free(ab);
        if (b_blank) |bb2| al.free(bb2);
    }

    if (fl.ignore_blank) {
        a_blank = al.alloc(bool, a.len) catch unreachable;
        b_blank = al.alloc(bool, b.len) catch unreachable;
        for (a, 0..) |line, i| {
            a_blank.?[i] = isBlank(line);
            if (!a_blank.?[i]) aa.append(al, line) catch unreachable;
        }
        for (b, 0..) |line, i| {
            b_blank.?[i] = isBlank(line);
            if (!b_blank.?[i]) bb.append(al, line) catch unreachable;
        }
    } else {
        for (a) |line| aa.append(al, line) catch unreachable;
        for (b) |line| bb.append(al, line) catch unreachable;
    }

    const filt_edits = LCS(aa.items, bb.items, fl, al);
    defer freeEdits(filt_edits, al);

    if (filt_edits.len == 0) return 0;

    if (fl.ignore_blank) {
        var only_blank = true;
        for (filt_edits) |e| {
            if (e.tag != .keep and !isBlank(e.text)) { only_blank = false; break; }
        }
        if (only_blank) return 0;
    }

    // Build the final edit list (with blank lines expanded if -B)
    var expanded: ?[]Edit = null;
    const edits = if (fl.ignore_blank) blk: {
        const e = expandBlanks(a, b, filt_edits, a_blank.?, b_blank.?, al);
        expanded = e;
        break :blk e;
    } else filt_edits;
    defer if (expanded) |e| { for (e) |ed| al.free(ed.text); al.free(e); };

    var first_change: usize = 0;
    while (first_change < edits.len and edits[first_change].tag == .keep) first_change += 1;
    if (first_change >= edits.len) return 0;

    core.writeAll(1, "--- ");
    core.writeAll(1, f1);
    core.writeAll(1, "\n");
    core.writeAll(1, "+++ ");
    core.writeAll(1, f2);
    core.writeAll(1, "\n");

    var any_diff = false;

    var last_change: usize = edits.len;
    while (last_change > 0 and edits[last_change - 1].tag == .keep) last_change -= 1;

    var old_idx: usize = 1;
    var new_idx: usize = 1;
    for (edits[0..first_change]) |e| {
        if (e.tag != .ins) old_idx += 1;
        if (e.tag != .del) new_idx += 1;
    }
    var old_cnt: usize = 0;
    var new_cnt: usize = 0;
    for (edits[first_change..last_change]) |e| {
        switch (e.tag) {
            .keep, .del => old_cnt += 1,
            else => {},
        }
        switch (e.tag) {
            .keep, .ins => new_cnt += 1,
            else => {},
        }
    }

    var tmpb: [64]u8 = undefined;
    core.writeAll(1, "@@ ");
    const old_i = if (old_cnt == 0) @as(usize, 0) else old_idx;
    const new_i = if (new_cnt == 0) @as(usize, 0) else new_idx;
    if (old_cnt == 0) {
        const s = std.fmt.bufPrint(&tmpb, "-{d},0 +", .{old_i}) catch unreachable;
        core.writeAll(1, s);
    } else if (old_cnt == 1) {
        const s = std.fmt.bufPrint(&tmpb, "-{d} +", .{old_i}) catch unreachable;
        core.writeAll(1, s);
    } else {
        const s = std.fmt.bufPrint(&tmpb, "-{d},{d} +", .{ old_i, old_cnt }) catch unreachable;
        core.writeAll(1, s);
    }
    if (new_cnt == 0) {
        const s = std.fmt.bufPrint(&tmpb, "{d},0 @@\n", .{new_i}) catch unreachable;
        core.writeAll(1, s);
    } else if (new_cnt == 1) {
        const s = std.fmt.bufPrint(&tmpb, "{d} @@\n", .{new_i}) catch unreachable;
        core.writeAll(1, s);
    } else {
        const s = std.fmt.bufPrint(&tmpb, "{d},{d} @@\n", .{ new_i, new_cnt }) catch unreachable;
        core.writeAll(1, s);
    }

    for (edits[first_change..last_change]) |e| {
        any_diff = true;
        switch (e.tag) {
            .keep => { core.writeAll(1, " "); core.writeAll(1, e.text); core.writeAll(1, "\n"); },
            .del => { core.writeAll(1, "-"); core.writeAll(1, e.text); core.writeAll(1, "\n"); },
            .ins => { core.writeAll(1, "+"); core.writeAll(1, e.text); core.writeAll(1, "\n"); },
        }
    }

    if (no_eol2) {
        core.writeAll(1, "\\ No newline at end of file\n");
    }

    return if (any_diff) 1 else 0;
}

fn expandBlanks(a: [][]const u8, b: [][]const u8, filt: []Edit, a_blank: []bool, b_blank: []bool, al: std.mem.Allocator) []Edit {
    var result = std.ArrayListAligned(Edit, null).empty;
    var ai: usize = 0;
    var bi: usize = 0;
    var fi: usize = 0;

    while (ai < a.len or bi < b.len or fi < filt.len) {
        if (ai < a.len and a_blank[ai]) {
            result.append(al, .{ .tag = .del, .text = al.dupe(u8, a[ai]) catch unreachable }) catch unreachable;
            ai += 1;
            continue;
        }
        if (bi < b.len and b_blank[bi]) {
            result.append(al, .{ .tag = .ins, .text = al.dupe(u8, b[bi]) catch unreachable }) catch unreachable;
            bi += 1;
            continue;
        }
        if (fi < filt.len) {
            switch (filt[fi].tag) {
                .del => { result.append(al, .{ .tag = .del, .text = al.dupe(u8, a[ai]) catch unreachable }) catch unreachable; ai += 1; fi += 1; },
                .ins => { result.append(al, .{ .tag = .ins, .text = al.dupe(u8, b[bi]) catch unreachable }) catch unreachable; bi += 1; fi += 1; },
                .keep => { result.append(al, .{ .tag = .keep, .text = al.dupe(u8, a[ai]) catch unreachable }) catch unreachable; ai += 1; bi += 1; fi += 1; },
            }
        } else break;
    }
    return result.toOwnedSlice(al) catch unreachable;
}



fn diffDirs(fl: *const Flags, d1: []const u8, d2: []const u8, a: std.mem.Allocator) u8 {
    const n1 = listDir(d1, a) orelse return 1;
    defer freeLines(n1, a);
    const n2 = listDir(d2, a) orelse return 1;
    defer freeLines(n2, a);

    var rc: u8 = 0;
    const alloc = std.heap.page_allocator;

    for (n1) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const p1 = tryJoin(d1, name, alloc) catch continue;
        defer alloc.free(p1);
        if (hasName(n2, name)) {
            const p2 = tryJoin(d2, name, alloc) catch continue;
            defer alloc.free(p2);
            const r1 = isReg(p1);
            const d1d = isDir(p1);
            const r2 = isReg(p2);
            const d2d = isDir(p2);
            const reg1 = r1 or d1d;
            const reg2 = r2 or d2d;
            if (reg1 and reg2) {
                const r = diff(fl, p1, p2, a);
                if (r > rc) rc = r;
            } else if (reg1 and !reg2) {
                if (d1d) {
                    core.writeAll(1, "Only in ");
                    core.writeAll(1, d2);
                    core.writeAll(1, ": ");
                    core.writeAll(1, name);
                    core.writeAll(1, "\n");
                } else {
                    core.writeAll(1, "File ");
                    core.writeAll(1, p2);
                    core.writeAll(1, " is not a regular file or directory and was skipped\n");
                }
            } else if (!reg1 and reg2) {
                if (d2d) {
                    core.writeAll(1, "Only in ");
                    core.writeAll(1, d1);
                    core.writeAll(1, ": ");
                    core.writeAll(1, name);
                    core.writeAll(1, "\n");
                } else {
                    core.writeAll(1, "File ");
                    core.writeAll(1, p1);
                    core.writeAll(1, " is not a regular file or directory and was skipped\n");
                }
            } else {
                core.writeAll(1, "File ");
                core.writeAll(1, p1);
                core.writeAll(1, " is not a regular file or directory and was skipped\n");
                core.writeAll(1, "File ");
                core.writeAll(1, p2);
                core.writeAll(1, " is not a regular file or directory and was skipped\n");
            }
        } else {
            const r = reportMissing(fl, d1, d2, p1, true, a);
            if (r > rc) rc = r;
        }
    }

    for (n2) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!hasName(n1, name)) {
            const p2 = tryJoin(d2, name, alloc) catch continue;
            defer alloc.free(p2);
            const r = reportMissing(fl, d1, d2, p2, false, a);
            if (r > rc) rc = r;
        }
    }

    return rc;
}

fn reportMissing(fl: *const Flags, d1: []const u8, d2: []const u8, path: []const u8, from_first: bool, a: std.mem.Allocator) u8 {
    const name = std.fs.path.basename(path);
    const dir = if (from_first) d1 else d2;
    if (isDir(path)) {
        core.writeAll(1, "Only in ");
        core.writeAll(1, dir);
        core.writeAll(1, ": ");
        core.writeAll(1, name);
        core.writeAll(1, "\n");
        return 0;
    }
    if (!isReg(path)) {
        core.writeAll(1, "File ");
        core.writeAll(1, path);
        core.writeAll(1, " is not a regular file or directory and was skipped\n");
        return 0;
    }
    if (fl.brief) {
        return 1;
    }
    if (fl.unified) {
        var no_eol_tmp = false;
        const lines = readLines(path, a, &no_eol_tmp) orelse return 1;
        defer freeLines(lines, a);
        const empty: [][]const u8 = &.{};
        const other_dir = if (from_first) d2 else d1;
        const p2 = tryJoin(other_dir, name, a) catch return 1;
        defer a.free(p2);
        if (from_first) {
            return unifiedDiff(fl, path, p2, lines, empty, false, false);
        } else {
            return unifiedDiff(fl, p2, path, empty, lines, false, false);
        }
    }
    return 1;
}

fn diffDirFile(fl: *const Flags, d: []const u8, f: []const u8, a: std.mem.Allocator) u8 {
    const names = listDir(d, a) orelse return 1;
    defer freeLines(names, a);
    var rc: u8 = 0;
    for (names) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const p = tryJoin(d, name, a) catch continue;
        defer a.free(p);
        if (!isReg(p) and !isDir(p)) {
            core.writeAll(1, "File ");
            core.writeAll(1, p);
            core.writeAll(1, " is not a regular file or directory and was skipped\n");
            continue;
        }
        const r = diff(fl, p, f, a);
        if (r > rc) rc = r;
    }
    return rc;
}

fn diffFileDir(fl: *const Flags, f: []const u8, d: []const u8, a: std.mem.Allocator) u8 {
    const names = listDir(d, a) orelse return 1;
    defer freeLines(names, a);
    var rc: u8 = 0;
    for (names) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const p = tryJoin(d, name, a) catch continue;
        defer a.free(p);
        if (!isReg(p) and !isDir(p)) {
            core.writeAll(1, "File ");
            core.writeAll(1, p);
            core.writeAll(1, " is not a regular file or directory and was skipped\n");
            continue;
        }
        const r = diff(fl, f, p, a);
        if (r > rc) rc = r;
    }
    return rc;
}

fn hasName(names: [][]const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn listDir(path: []const u8, a: std.mem.Allocator) ?[][]const u8 {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const d = core.c.opendir(buf[0..path.len :0].ptr) orelse return null;
    defer _ = core.c.closedir(d);
    var names = std.ArrayListAligned([]const u8, null).empty;
    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const dup = a.dupe(u8, name) catch return null;
        names.append(a, dup) catch return null;
    }
    const result = names.toOwnedSlice(a) catch return null;
    std.sort.insertion([]const u8, result, {}, struct {
        fn less(_: void, a2: []const u8, b2: []const u8) bool {
            return std.mem.lessThan(u8, a2, b2);
        }
    }.less);
    return result;
}

fn tryJoin(dir: []const u8, file: []const u8, a: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayListAligned(u8, null).empty;
    try result.appendSlice(a, dir);
    if (dir.len > 0 and dir[dir.len - 1] != '/') try result.append(a, '/');
    try result.appendSlice(a, file);
    return result.toOwnedSlice(a);
}
