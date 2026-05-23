const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "fold", .main = main };
pub fn main(args: [][]const u8) u8 {
    var width: usize = 80;
    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "-w")) {
        i += 1;
        if (i >= args.len) return core.die(1, "fold: missing number after -w\n", .{});
        width = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "fold: invalid width\n", .{});
        i += 1;
    }
    var reader = core.LineReader.init(0);
    while (reader.next()) |line| {
        var start: usize = 0;
        while (start < line.len) {
            const end = @min(start + width, line.len);
            core.writeAll(1, line[start..end]);
            core.writeAll(1, "\n");
            start = end;
        }
    }
    return 0;
}
