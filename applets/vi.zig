const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "vi", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "vi: missing file\n", .{});
    const file = args[1];
    var fbuf: [4096:0]u8 = undefined;
    if (file.len >= fbuf.len) return core.die(1, "vi: path too long\n", .{});
    @memcpy(fbuf[0..file.len], file);
    fbuf[file.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "vi: cannot open '{s}'\n", .{file});
    defer _ = core.c.close(fd);
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, fd, 1024 * 1024) catch return core.die(1, "vi: read error\n", .{});
    defer alloc.free(data);
    var line_no: usize = 1;
    var pos: usize = 0;
    var lbuf: [64]u8 = undefined;
    while (pos < data.len) {
        var end = pos;
        while (end < data.len and data[end] != '\n') end += 1;
        const line = data[pos..end];
        const num = std.fmt.bufPrint(&lbuf, "{d:>6}  ", .{line_no}) catch "";
        core.writeAll(1, num);
        core.writeAll(1, line);
        core.writeAll(1, "\n");
        pos = end + 1;
        line_no += 1;
    }
    return 0;
}
