const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "expand", .main = main };
pub fn main(args: [][]const u8) u8 {
    var tabstop: usize = 8;
    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "-t")) {
        i += 1;
        if (i >= args.len) return core.die(1, "expand: missing number after -t\n", .{});
        tabstop = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "expand: invalid tabstop\n", .{});
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);
    var buf: [1024 * 1024]u8 = undefined;
    var pos: usize = 0;
    for (data) |ch| {
        if (ch == '\t') {
            const spaces = tabstop - (pos % tabstop);
            var j: usize = 0;
            while (j < spaces) : (j += 1) {
                buf[pos + j] = ' ';
            }
            pos += spaces;
        } else {
            buf[pos] = ch;
            pos += 1;
        }
    }
    core.writeAll(1, buf[0..pos]);
    return 0;
}
