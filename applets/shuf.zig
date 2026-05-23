const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "shuf", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;
    var lines = std.ArrayListAligned([]const u8, null).empty;
    defer {
        for (lines.items) |l| alloc.free(l);
        lines.deinit(alloc);
    }
    var reader = core.LineReader.init(0);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch return 1;
        lines.append(alloc, dup) catch return 1;
    }
    if (lines.items.len == 0) return 0;
    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(core.c.time(null))));
    const rand = prng.random();
    var i: usize = lines.items.len;
    while (i > 1) {
        i -= 1;
        const j = rand.uintLessThan(usize, i + 1);
        const tmp = lines.items[i];
        lines.items[i] = lines.items[j];
        lines.items[j] = tmp;
    }
    for (lines.items) |line| {
        core.writeAll(1, line);
        core.writeAll(1, "\n");
    }
    return 0;
}
