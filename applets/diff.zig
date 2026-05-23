const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "diff", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                else => return core.die(2, "diff: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (i + 2 > args.len) return core.die(2, "diff: missing file arguments\n", .{});
    const file1 = args[i];
    const file2 = args[i + 1];

    const alloc = std.heap.page_allocator;

    const lines1 = readLines(file1, alloc) orelse
        return core.die(2, "diff: {s}: No such file or directory\n", .{file1});
    defer alloc.free(lines1);

    const lines2 = readLines(file2, alloc) orelse
        return core.die(2, "diff: {s}: No such file or directory\n", .{file2});
    defer alloc.free(lines2);

    var buf: [8192]u8 = undefined;
    var differed = false;
    const max = @max(lines1.len, lines2.len);

    for (0..max) |j| {
        const l1 = if (j < lines1.len) lines1[j] else "";
        const l2 = if (j < lines2.len) lines2[j] else "";
        if (!std.mem.eql(u8, l1, l2)) {
            differed = true;
            const info = std.fmt.bufPrint(&buf, "{d}c{d}\n", .{j + 1, j + 1}) catch "";
            core.writeAll(1, info);
            core.writeAll(1, "< ");
            core.writeAll(1, l1);
            core.writeAll(1, "\n");
            core.writeAll(1, "---\n");
            core.writeAll(1, "> ");
            core.writeAll(1, l2);
            core.writeAll(1, "\n");
        }
    }

    return if (differed) 1 else 0;
}

fn readLines(name: []const u8, alloc: std.mem.Allocator) ?[][]const u8 {
    var fbuf: [4096:0]u8 = undefined;
    if (name.len >= fbuf.len) return null;
    @memcpy(fbuf[0..name.len], name);
    fbuf[name.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);

    var lines: std.ArrayListAligned([]const u8, null) = .empty;
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch return null;
        lines.append(alloc, dup) catch return null;
    }
    return lines.toOwnedSlice(alloc) catch return null;
}
