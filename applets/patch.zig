const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "patch", .main = main };
pub fn main(args: [][]const u8) u8 {
    var strip: usize = 0;
    var input_file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-p")) {
                i += 1;
                if (i >= args.len) return core.die(1, "patch: missing number after -p\n", .{});
                strip = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "patch: invalid -p value\n", .{});
            } else if (std.mem.eql(u8, arg, "-i")) {
                i += 1;
                if (i >= args.len) return core.die(1, "patch: missing file after -i\n", .{});
                input_file = args[i];
            } else if (std.mem.eql(u8, arg, "--")) {
                i += 1;
                break;
            } else return core.die(1, "patch: unknown flag '{s}'\n", .{arg});
        } else break;
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const patch_lines = readPatchLines(input_file, alloc) orelse return 1;
    defer {
        for (patch_lines) |l| alloc.free(l);
        alloc.free(patch_lines);
    }
    var target_file: ?[]const u8 = null;
    var hunks: std.ArrayListAligned(Hunk, null) = .empty;
    defer hunks.deinit(alloc);
    var pi: usize = 0;
    while (pi < patch_lines.len) {
        const line = patch_lines[pi];
        if (std.mem.startsWith(u8, line, "--- ")) {
            const f = line[4..];
            target_file = stripPath(f, strip);
        } else if (std.mem.startsWith(u8, line, "+++ ")) {
            const f = line[4..];
            target_file = stripPath(f, strip);
        } else if (std.mem.startsWith(u8, line, "@@")) {
            const hunk = parseHunk(patch_lines, &pi, alloc) catch {
                core.eprint("patch: failed to parse hunk\n", .{});
                return 1;
            };
            hunks.append(alloc, hunk) catch return 1;
        }
        pi += 1;
    }
    const tfile = target_file orelse return core.die(1, "patch: no target file found in patch\n", .{});
    var fbuf: [4096:0]u8 = undefined;
    if (tfile.len >= fbuf.len) return core.die(1, "patch: path too long\n", .{});
    @memcpy(fbuf[0..tfile.len], tfile);
    fbuf[tfile.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "patch: cannot open target file '{s}'\n", .{tfile});
    defer _ = core.c.close(fd);
    const file_data = core.readAll(alloc, fd, 1024 * 1024) catch return core.die(1, "patch: read error\n", .{});
    defer alloc.free(file_data);
    const file_lines = splitLines(file_data, alloc) catch return 1;
    defer {
        for (file_lines) |l| alloc.free(l);
        alloc.free(file_lines);
    }
    var result = std.ArrayListAligned([]const u8, null).empty;
    defer result.deinit(alloc);
    var file_idx: usize = 0;
    for (hunks.items) |hunk| {
        while (file_idx < hunk.old_start - 1 and file_idx < file_lines.len) {
            result.append(alloc, file_lines[file_idx]) catch return 1;
            file_idx += 1;
        }
        for (hunk.new_lines) |nl| {
            const dup = alloc.dupe(u8, nl) catch return 1;
            result.append(alloc, dup) catch return 1;
        }
        file_idx += hunk.old_count;
    }
    while (file_idx < file_lines.len) {
        result.append(alloc, file_lines[file_idx]) catch return 1;
        file_idx += 1;
    }
    _ = core.c.close(fd);
    var out_fbuf: [4096:0]u8 = undefined;
    @memcpy(out_fbuf[0..tfile.len], tfile);
    out_fbuf[tfile.len] = 0;
    const out_fd = core.c.open(&out_fbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (out_fd < 0) return core.die(1, "patch: cannot write '{s}'\n", .{tfile});
    defer _ = core.c.close(out_fd);
    for (result.items) |rl| {
        core.writeAll(out_fd, rl);
        core.writeAll(out_fd, "\n");
    }
    return 0;
}
fn stripPath(path: []const u8, n: usize) []const u8 {
    var p = path;
    var count: usize = 0;
    while (count < n) {
        if (std.mem.indexOfScalar(u8, p, '/')) |idx| {
            p = p[idx + 1..];
            count += 1;
        } else break;
    }
    return p;
}
const Hunk = struct {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    new_lines: [][]const u8,
};
fn parseHunk(lines: [][]const u8, pi: *usize, alloc: std.mem.Allocator) !Hunk {
    const hdr = lines[pi.*];
    var hdr_end: usize = 2;
    while (hdr_end < hdr.len and hdr[hdr_end] != '@') hdr_end += 1;
    const spec = std.mem.trim(u8, hdr[2..hdr_end], " \t");
    var old_s: usize = 0;
    var old_c: usize = 1;
    var new_s: usize = 0;
    var new_c: usize = 1;
    var parts = std.mem.splitScalar(u8, spec, ' ');
    while (parts.next()) |part| {
        if (part.len > 0 and part[0] == '-') {
            var rest = part[1..];
            if (std.mem.indexOfScalar(u8, rest, ',')) |comma| {
                old_s = try std.fmt.parseInt(usize, rest[0..comma], 10);
                old_c = try std.fmt.parseInt(usize, rest[comma + 1 ..], 10);
            } else {
                old_s = try std.fmt.parseInt(usize, rest, 10);
            }
        } else if (part.len > 0 and part[0] == '+') {
            var rest = part[1..];
            if (std.mem.indexOfScalar(u8, rest, ',')) |comma| {
                new_s = try std.fmt.parseInt(usize, rest[0..comma], 10);
                new_c = try std.fmt.parseInt(usize, rest[comma + 1 ..], 10);
            } else {
                new_s = try std.fmt.parseInt(usize, rest, 10);
            }
        }
    }
    var new_lines = std.ArrayListAligned([]const u8, null).empty;
    pi.* += 1;
    while (pi.* < lines.len) {
        const l = lines[pi.*];
        if (std.mem.startsWith(u8, l, "@@")) break;
        if (l.len > 0 and l[0] == '+') {
            const dup = try alloc.dupe(u8, l[1..]);
            try new_lines.append(alloc, dup);
        } else if (l.len > 0 and l[0] == ' ') {
            const dup = try alloc.dupe(u8, l[1..]);
            try new_lines.append(alloc, dup);
        }
        pi.* += 1;
    }
    pi.* -= 1;
    return Hunk{
        .old_start = old_s,
        .old_count = old_c,
        .new_start = new_s,
        .new_count = new_c,
        .new_lines = try new_lines.toOwnedSlice(alloc),
    };
}
fn readPatchLines(file: ?[]const u8, alloc: std.mem.Allocator) ?[][]const u8 {
    var fd: c_int = 0;
    var needs_close = false;
    if (file) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return null;
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return null;
        needs_close = true;
    }
    defer {
        if (needs_close) _ = core.c.close(fd);
    }
    var lines = std.ArrayListAligned([]const u8, null).empty;
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch return null;
        lines.append(alloc, dup) catch return null;
    }
    return lines.toOwnedSlice(alloc) catch return null;
}
fn splitLines(data: []const u8, alloc: std.mem.Allocator) ![][]const u8 {
    var lines = std.ArrayListAligned([]const u8, null).empty;
    var pos: usize = 0;
    while (pos < data.len) {
        var end = pos;
        while (end < data.len and data[end] != '\n') end += 1;
        const dup = try alloc.dupe(u8, data[pos..end]);
        try lines.append(alloc, dup);
        pos = end + 1;
    }
    return lines.toOwnedSlice(alloc);
}
