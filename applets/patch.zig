const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "patch", .main = main };

const HunkLine = struct { tag: enum { ctx, add, del }, text: []const u8 };
const Hunk = struct {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    lines: []HunkLine,
};

pub fn main(args: [][]const u8) u8 {
    var strip: usize = 0;
    var input_file: ?[]const u8 = null;
    var arg_file: ?[]const u8 = null;
    var reverse = false;
    var ignore_mismatch = false;

    var i: usize = 1;
    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--")) { i += 1; break; }
        if (a.len < 2 or a[0] != '-') break;
        if (std.mem.eql(u8, a, "-R")) { reverse = true; i += 1; continue; }
        if (std.mem.eql(u8, a, "-N")) { ignore_mismatch = true; i += 1; continue; }
        if (std.mem.startsWith(u8, a, "-p")) {
            if (a.len > 2) { strip = std.fmt.parseInt(usize, a[2..], 10) catch return 1; }
            else { i += 1; if (i >= args.len) return 1; strip = std.fmt.parseInt(usize, args[i], 10) catch return 1; }
            i += 1; continue;
        }
        if (std.mem.eql(u8, a, "-i")) { i += 1; if (i >= args.len) return 1; input_file = args[i]; i += 1; continue; }
        return 1;
    }
    if (i < args.len) { arg_file = args[i]; i += 1; }
    if (i < args.len) { input_file = args[i]; i += 1; }

    const alloc = std.heap.page_allocator;
    const patch = readLines(input_file, alloc) orelse return 1;
    defer {
        for (patch) |l| alloc.free(l);
        alloc.free(patch);
    }

    var target_file: ?[]const u8 = null;
    var hunks = std.ArrayListAligned(Hunk, null).empty;
    defer hunks.deinit(alloc);
    var creating = false;
    var pi: usize = 0;
    while (pi < patch.len) {
        const line = patch[pi];
        if (std.mem.startsWith(u8, line, "--- ")) {
            var name = line[4..];
            for (name, 0..) |c, idx| { if (c == ' ' or c == '\t') { name = name[0..idx]; break; } }
            const p = stripPath(name, strip);
            if (std.mem.eql(u8, p, "/dev/null")) { creating = true; }
            if (target_file == null and arg_file == null) target_file = p;
        } else if (std.mem.startsWith(u8, line, "+++ ")) {
            var name = line[4..];
            for (name, 0..) |c, idx| { if (c == ' ' or c == '\t') { name = name[0..idx]; break; } }
            const p = stripPath(name, strip);
            if (arg_file) |af| { target_file = af; } else { target_file = p; }
        } else if (std.mem.startsWith(u8, line, "@@")) {
            const h = parseHunk(patch, &pi, alloc, reverse) catch {
                core.eprint("patch: failed to parse hunk\n", .{});
                return 1;
            };
            hunks.append(alloc, h) catch return 1;
        }
        pi += 1;
    }

    const tfile = target_file orelse return core.die(1, "patch: no target file found in patch\n", .{});

    const has_file = isReg(tfile);
    var existing = std.ArrayListAligned([]const u8, null).empty;
    defer existing.deinit(alloc);
    if (has_file) {
        var buf: [4096:0]u8 = undefined;
        @memcpy(buf[0..tfile.len], tfile);
        buf[tfile.len] = 0;
        const fd = core.c.open(buf[0..tfile.len :0].ptr, core.c.O_RDONLY);
        if (fd >= 0) {
            defer _ = core.c.close(fd);
            if (core.readAll(alloc, fd, 1024 * 1024)) |data| {
                var pos: usize = 0;
                while (pos < data.len) {
                    var end = pos;
                    while (end < data.len and data[end] != '\n') end += 1;
                    existing.append(alloc, alloc.dupe(u8, data[pos..end]) catch "") catch {};
                    pos = end + 1;
                }
                alloc.free(data);
            } else |_| {}
        }
    }

    var result = std.ArrayListAligned([]const u8, null).empty;
    defer result.deinit(alloc);
    var file_idx: usize = 0;
    var any_failed = false;

    if (!has_file and !creating) {
        core.writeAll(1, "patching file ");
        core.writeAll(1, tfile);
        core.writeAll(1, "\n");
    } else if (creating and !has_file) {
        core.writeAll(1, "creating ");
        core.writeAll(1, tfile);
        core.writeAll(1, "\n");
        // For a new file, just apply hunks directly
        for (hunks.items) |hunk| {
            const res = applyHunk(&hunk, existing.items, &file_idx, &result, ignore_mismatch, alloc);
            if (res > 0) any_failed = true;
        }
    } else if (has_file) {
        core.writeAll(1, "patching file ");
        core.writeAll(1, tfile);
        core.writeAll(1, "\n");
        for (hunks.items) |hunk| {
            const res = applyHunk(&hunk, existing.items, &file_idx, &result, ignore_mismatch, alloc);
            if (res > 0) any_failed = true;
        }
    }

    while (file_idx < existing.items.len) {
        const d = alloc.dupe(u8, existing.items[file_idx]) catch return 1;
        result.append(alloc, d) catch return 1;
        file_idx += 1;
    }

    var obuf: [4096:0]u8 = undefined;
    if (tfile.len >= obuf.len) return 1;
    @memcpy(obuf[0..tfile.len], tfile);
    obuf[tfile.len] = 0;
    const ofd = core.c.open(obuf[0..tfile.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (ofd < 0) return core.die(1, "patch: can't open '{s}': No such file or directory\n", .{tfile});
    defer _ = core.c.close(ofd);
    for (result.items) |rl| {
        core.writeAll(ofd, rl);
        core.writeAll(ofd, "\n");
    }

    return if (any_failed) 1 else 0;
}

fn parseHunk(lines: [][]const u8, pi: *usize, alloc: std.mem.Allocator, reverse: bool) !Hunk {
    const hdr = lines[pi.*];
    var end: usize = 2;
    while (end < hdr.len and hdr[end] != '@') end += 1;
    const spec = std.mem.trim(u8, hdr[2..end], " \t");
    var old_s: usize = 0; var old_c: usize = 1;
    var new_s: usize = 0; var new_c: usize = 1;
    var parts = std.mem.splitScalar(u8, spec, ' ');
    while (parts.next()) |part| {
        if (part.len > 0 and part[0] == '-') {
            const r = part[1..];
            if (std.mem.indexOfScalar(u8, r, ',')) |comma| {
                old_s = try std.fmt.parseInt(usize, r[0..comma], 10);
                old_c = try std.fmt.parseInt(usize, r[comma + 1 ..], 10);
            } else { old_s = try std.fmt.parseInt(usize, r, 10); }
        } else if (part.len > 0 and part[0] == '+') {
            const r = part[1..];
            if (std.mem.indexOfScalar(u8, r, ',')) |comma| {
                new_s = try std.fmt.parseInt(usize, r[0..comma], 10);
                new_c = try std.fmt.parseInt(usize, r[comma + 1 ..], 10);
            } else { new_s = try std.fmt.parseInt(usize, r, 10); }
        }
    }

    var hlines = std.ArrayListAligned(HunkLine, null).empty;
    pi.* += 1;
    while (pi.* < lines.len) {
        const l = lines[pi.*];
        if (l.len > 0 and l[0] == '@' and std.mem.indexOf(u8, l, "@@") != null) break;
        if (l.len > 0 and l[0] == '-' and l.len >= 2 and l[1] == '-') break; // scissor line
        if (l.len == 0) { pi.* += 1; continue; }
        const tag: HunkLine = switch (l[0]) {
            '-' => .{ .tag = .del, .text = try alloc.dupe(u8, l[1..]) },
            '+' => .{ .tag = .add, .text = try alloc.dupe(u8, l[1..]) },
            ' ' => .{ .tag = .ctx, .text = try alloc.dupe(u8, l[1..]) },
            '\\' => { pi.* += 1; continue; }, // no newline at eof
            else => { pi.* += 1; continue; },
        };
        try hlines.append(alloc, tag);
        pi.* += 1;
    }
    pi.* -= 1;

    if (reverse) {
        var rev = std.ArrayListAligned(HunkLine, null).empty;
        for (hlines.items) |hl| {
            try rev.append(alloc, switch (hl.tag) {
                .add => HunkLine{ .tag = .del, .text = try alloc.dupe(u8, hl.text) },
                .del => HunkLine{ .tag = .add, .text = try alloc.dupe(u8, hl.text) },
                .ctx => HunkLine{ .tag = .ctx, .text = try alloc.dupe(u8, hl.text) },
            });
        }
        return Hunk{
            .old_start = if (new_s > 0) new_s else 1,
            .old_count = new_c,
            .new_start = if (old_s > 0) old_s else 1,
            .new_count = old_c,
            .lines = try rev.toOwnedSlice(alloc),
        };
    }
    return Hunk{
        .old_start = if (old_s > 0) old_s else 1,
        .old_count = old_c,
        .new_start = if (new_s > 0) new_s else 1,
        .new_count = new_c,
        .lines = try hlines.toOwnedSlice(alloc),
    };
}

fn applyHunk(hunk: *const Hunk, file: [][]const u8, idx: *usize, result: *std.ArrayListAligned([]const u8, null), ignore: bool, alloc: std.mem.Allocator) u8 {
    // Build the old (deleted + context) sequence and new (inserted + context) sequence
    var old_sq = std.ArrayListAligned([]const u8, null).empty;
    defer old_sq.deinit(alloc);
    var new_sq = std.ArrayListAligned([]const u8, null).empty;
    defer new_sq.deinit(alloc);
    for (hunk.lines) |hl| {
        switch (hl.tag) {
            .del, .ctx => old_sq.append(alloc, hl.text) catch return 1,
            else => {},
        }
        switch (hl.tag) {
            .add, .ctx => new_sq.append(alloc, hl.text) catch return 1,
            else => {},
        }
    }

    const start = if (hunk.old_start > 0) hunk.old_start - 1 else @as(usize, 0);
    var search = start;
    if (search > 0) search -= 1;

    // Try to match old sequence (forward application)
    var found_at: ?usize = null;
    var reversed = false;

    // Handle empty file / insertion hunk
    if (old_sq.items.len == 0) {
        found_at = idx.*;
    } else for (0..@min(20, if (file.len > idx.* + 5) file.len - idx.* else 5 + idx.*)) |try_i| {
        const pos = search + try_i;
        if (pos >= file.len) break;
        if (pos < idx.*) continue;
        if (pos + old_sq.items.len > file.len) continue;
        var ok = true;
        for (old_sq.items, 0..) |tl, li| {
            if (pos + li >= file.len or !std.mem.eql(u8, tl, file[pos + li])) { ok = false; break; }
        }
        if (ok) {
            // Check if new_seq also matches (hunk already applied)
            if (pos + new_sq.items.len <= file.len) {
                var both_ok = true;
                for (new_sq.items, 0..) |nl, li| {
                    if (pos + li >= file.len or !std.mem.eql(u8, nl, file[pos + li])) { both_ok = false; break; }
                }
                if (both_ok) {
                    found_at = pos;
                    reversed = true;
                    break;
                }
            }
            if (!reversed) {
                found_at = pos;
                break;
            }
        }
    }

    // If not found, try to match new sequence (already applied as reverse)
    if (found_at == null) {
        for (0..@min(20, file.len)) |try_i| {
            const pos = try_i;
            if (pos < idx.*) continue;
            if (pos + new_sq.items.len > file.len) break;
            var ok = true;
            for (new_sq.items, 0..) |tl, li| {
                if (pos + li >= file.len or !std.mem.eql(u8, tl, file[pos + li])) { ok = false; break; }
            }
            if (ok) { found_at = pos; reversed = true; break; }
        }
    }

    if (found_at == null) {
        // Hunk failed entirely
        core.writeAll(1, "Hunk 1 FAILED 1/1.\n"); // simplified hunk numbering
        // Copy remaining file content as-is
        while (idx.* < file.len) {
            result.append(alloc, alloc.dupe(u8, file[idx.*]) catch "") catch {};
            idx.* += 1;
        }
        return 1;
    }

    const pos = found_at.?;

    // Copy lines before hunk
    while (idx.* < pos) {
        result.append(alloc, alloc.dupe(u8, file[idx.*]) catch "") catch {};
        idx.* += 1;
    }

    if (reversed) {
        if (ignore) {
            // Silently skip, file is unchanged - copy matched lines
            for (new_sq.items) |nl| {
                result.append(alloc, alloc.dupe(u8, nl) catch "") catch {};
            }
            idx.* += new_sq.items.len;
            return 0;
        }
        // Output "Possibly reversed hunk" message
        core.writeAll(1, "Possibly reversed hunk 1 at ");
        var nb: [32]u8 = undefined;
        const at = hunk.old_start + hunk.new_count;
        const ns = std.fmt.bufPrint(&nb, "{d}\n", .{at}) catch "";
        core.writeAll(1, ns);
        core.writeAll(1, "Hunk 1 FAILED 1/1.\n");

        // Show hunk content as it would be applied
        for (hunk.lines) |hl| {
            switch (hl.tag) {
                .ctx => { core.writeAll(1, " "); core.writeAll(1, hl.text); core.writeAll(1, "\n"); },
                .add => { core.writeAll(1, "+"); core.writeAll(1, hl.text); core.writeAll(1, "\n"); },
                .del => { core.writeAll(1, "-"); core.writeAll(1, hl.text); core.writeAll(1, "\n"); },
            }
        }

        // File stays unchanged - copy the matched lines as-is
        for (new_sq.items) |nl| {
            result.append(alloc, alloc.dupe(u8, nl) catch "") catch {};
        }
        idx.* += new_sq.items.len;
        return 1;
    }

    // Normal application: skip old lines, insert new lines
    idx.* += old_sq.items.len;
    for (new_sq.items) |nl| {
        result.append(alloc, alloc.dupe(u8, nl) catch "") catch {};
    }

    return 0;
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

fn readLines(file: ?[]const u8, alloc: std.mem.Allocator) ?[][]const u8 {
    const fd = if (file) |f| blk: {
        var buf: [4096:0]u8 = undefined;
        if (f.len >= buf.len) return null;
        @memcpy(buf[0..f.len], f);
        buf[f.len] = 0;
        const fd2 = core.c.open(buf[0..f.len :0].ptr, core.c.O_RDONLY);
        if (fd2 < 0) return null;
        break :blk fd2;
    } else 0;
    defer { if (file != null) _ = core.c.close(fd); }
    var lines = std.ArrayListAligned([]const u8, null).empty;
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch return null;
        lines.append(alloc, dup) catch return null;
    }
    return lines.toOwnedSlice(alloc) catch return null;
}

fn stripPath(p: []const u8, n: usize) []const u8 {
    var path = p;
    var count: usize = 0;
    while (count < n) {
        // Skip consecutive slashes
        while (path.len > 0 and path[0] == '/') path = path[1..];
        if (std.mem.indexOfScalar(u8, path, '/')) |idx| {
            path = path[idx..];
            while (path.len > 0 and path[0] == '/') path = path[1..];
            count += 1;
        } else break;
    }
    return path;
}
