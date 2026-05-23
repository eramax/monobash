const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "realpath", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: realpath FILE...\n", .{});
    var rc: u8 = 0;
    for (args[1..]) |arg| {
        var inbuf: [4096:0]u8 = undefined;
        var outbuf: [4096:0]u8 = undefined;
        if (arg.len >= inbuf.len) { rc = 1; continue; }
        @memcpy(inbuf[0..arg.len], arg);
        inbuf[arg.len] = 0;
        const res = core.c.realpath(&inbuf, &outbuf);
        if (res == null) {
            core.eprint("realpath: {s}: No such file or directory\n", .{arg});
            rc = 1;
            continue;
        }
        const len = std.mem.indexOfScalar(u8, &outbuf, 0) orelse outbuf.len;
        core.writeAll(1, outbuf[0..len]);
        core.writeAll(1, "\n");
    }
    return rc;
}
