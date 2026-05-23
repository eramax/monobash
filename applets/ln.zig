const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ln", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    var i: usize = 1;
    var sym = false;
    if (std.mem.eql(u8, args[i], "-s")) {
        sym = true;
        i += 1;
    }
    const target = args[i];
    const link_name = args[i + 1];
    var buf: [4096:0]u8 = undefined;
    var buf2: [4096:0]u8 = undefined;
    if (target.len >= buf.len or link_name.len >= buf2.len) return 1;
    @memcpy(buf[0..target.len], target);
    buf[target.len] = 0;
    @memcpy(buf2[0..link_name.len], link_name);
    buf2[link_name.len] = 0;
    const rc = if (sym)
        core.c.symlink(&buf, &buf2)
    else
        core.c.link(&buf, &buf2);
    return if (rc == 0) 0 else 1;
}
