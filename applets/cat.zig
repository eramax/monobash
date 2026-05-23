const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cat", .main = main };

pub fn main(args: [][]const u8) u8 {
    const files = args[1..];
    if (files.len == 0) {
        var reader = core.LineReader.init(0);
        while (reader.next()) |line| {
            core.writeAll(1, line);
            core.writeAll(1, "\n");
        }
        return 0;
    }
    var iter = core.FileIter.init(args);
    while (iter.next()) |entry| {
        const buf = core.readAll(std.heap.page_allocator, entry.fd, 1024 * 1024) catch {
            core.eprint("cat: read error\n", .{});
            continue;
        };
        defer std.heap.page_allocator.free(buf);
        core.writeAll(1, buf);
    }
    return 0;
}
