const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ptx", .main = main };

pub fn main(args: [][]const u8) u8 {
    var file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (args[i].len > 0 and args[i][0] == '-') {
            return core.die(1, "ptx: unknown option: {s}\n", .{args[i]});
        }
        file = args[i];
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = if (file) |f| blk: {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return core.die(1, "ptx: path too long\n", .{});
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "ptx: {s}: No such file\n", .{f});
        defer _ = core.c.close(fd);
        break :blk core.readAll(alloc, fd, 1024 * 1024 * 16) catch return 1;
    } else (core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1);
    defer alloc.free(data);

    var lines: std.ArrayListAligned([]const u8, null) = .empty;
    defer lines.deinit(alloc);
    var start: usize = 0;
    while (start < data.len) {
        const end = std.mem.indexOfScalar(u8, data[start..], '\n') orelse data.len - start;
        const line = data[start .. start + end];
        lines.append(alloc, line) catch return 1;
        start += end + 1;
        if (start >= data.len) break;
    }

    var entries: std.ArrayListAligned([]u8, null) = .empty;
    defer {
        for (entries.items) |e| alloc.free(e);
        entries.deinit(alloc);
    }

    for (lines.items) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        var words: std.ArrayListAligned([]const u8, null) = .empty;
        defer words.deinit(alloc);
        var wstart: usize = 0;
        while (wstart < trimmed.len) {
            while (wstart < trimmed.len and trimmed[wstart] == ' ') wstart += 1;
            if (wstart >= trimmed.len) break;
            var wend = wstart;
            while (wend < trimmed.len and trimmed[wend] != ' ') wend += 1;
            words.append(alloc, trimmed[wstart..wend]) catch return 1;
            wstart = wend;
        }
        for (words.items, 0..) |_, wi| {
            var entry = std.ArrayListAligned(u8, null).empty;
            defer entry.deinit(alloc);
            for (words.items[wi..]) |w| {
                entry.appendSlice(alloc, w) catch return 1;
                entry.append(alloc, ' ') catch return 1;
            }
            entry.append(alloc, '\t') catch return 1;
            for (words.items[0..wi]) |w| {
                entry.appendSlice(alloc, w) catch return 1;
                entry.append(alloc, ' ') catch return 1;
            }
            const e = entry.toOwnedSlice(alloc) catch return 1;
            entries.append(alloc, e) catch return 1;
        }
    }

    std.sort.block([]u8, entries.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (entries.items) |e| {
        core.writeAll(1, e);
        core.writeAll(1, "\n");
    }
    return 0;
}
