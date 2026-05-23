const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "chcon", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: chcon CONTEXT FILE...\n", .{});
    const context = args[1];
    var ctx_buf: [4096:0]u8 = undefined;
    if (context.len >= ctx_buf.len) return 1;
    @memcpy(ctx_buf[0..context.len], context);
    ctx_buf[context.len] = 0;
    var rc: u8 = 0;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        var fbuf: [4096:0]u8 = undefined;
        if (args[i].len >= fbuf.len) { rc = 1; continue; }
        @memcpy(fbuf[0..args[i].len], args[i]);
        fbuf[args[i].len] = 0;
        core.writeAll(1, "chcon: SELinux not available, context not set\n");
        rc = 1;
    }
    return rc;
}
