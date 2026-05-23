const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "modinfo", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: modinfo MODULE\n", .{});

    const module = args[1];
    const fd = core.openReadName("/proc/modules") orelse return core.die(1, "modinfo: cannot open /proc/modules\n", .{});
    defer _ = core.c.close(fd);
    const data = core.readAll(std.heap.page_allocator, fd, 65536) catch return 1;
    defer std.heap.page_allocator.free(data);

    var pos: usize = 0;
    while (pos < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[pos..], '\n') orelse (data.len - pos);
        const line = data[pos..][0..nl];
        pos += nl + 1;
        if (line.len == 0) continue;

        const space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const name = line[0..space];
        if (std.mem.eql(u8, name, module)) {
            core.writeAll(1, line);
            core.writeAll(1, "\n");
            return 0;
        }
    }
    return core.die(1, "modinfo: module '{s}' not found\n", .{module});
}
