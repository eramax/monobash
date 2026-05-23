const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "ttysize", .main = main };
pub fn main(args: [][]const u8) u8 {
    var ws: core.c.struct_winsize = undefined;
    var w: u32 = 80;
    var h: u32 = 24;
    if (core.c.ioctl(0, core.c.TIOCGWINSZ, &ws) >= 0 or
        core.c.ioctl(1, core.c.TIOCGWINSZ, &ws) >= 0 or
        core.c.ioctl(2, core.c.TIOCGWINSZ, &ws) >= 0)
    {
        w = ws.ws_col;
        h = ws.ws_row;
    }
    if (args.len > 1) {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "w")) {
                var buf: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{w}) catch return 1;
                core.writeAll(1, s);
            }
            if (std.mem.eql(u8, args[i], "h")) {
                var buf: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{h}) catch return 1;
                core.writeAll(1, s);
            }
            if (i + 1 < args.len) core.writeAll(1, " ");
        }
    } else {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d} {d}", .{w, h}) catch return 1;
        core.writeAll(1, s);
    }
    core.writeAll(1, "\n");
    return 0;
}
