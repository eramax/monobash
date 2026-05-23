const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "rev", .main = main };
pub fn main(args: [][]const u8) u8 {
    const file = if (args.len > 1) args[1] else "";
    var fd: c_int = 0;
    if (file.len > 0) {
        var fbuf: [4096:0]u8 = undefined;
        if (file.len >= fbuf.len) return core.die(1, "rev: path too long\n", .{});
        @memcpy(fbuf[0..file.len], file);
        fbuf[file.len] = 0;
        fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "rev: cannot open '{s}'\n", .{file});
    }
    var reader = core.LineReader.init(fd);
    var rbuf: [8192]u8 = undefined;
    while (reader.nextWithTerminator()) |entry| {
        var line = entry.line;
        var terminated = entry.terminated;
        if (std.mem.indexOfScalar(u8, line, 0)) |nul_pos| {
            line = line[0..nul_pos];
            terminated = false;
        }
        var j: usize = 0;
        while (j < line.len) {
            rbuf[j] = line[line.len - 1 - j];
            j += 1;
        }
        core.writeAll(1, rbuf[0..line.len]);
        if (terminated) core.writeAll(1, "\n");
    }
    if (file.len > 0 and fd > 0) _ = core.c.close(fd);
    return 0;
}
