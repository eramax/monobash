const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "echo", .main = main };
pub fn main(args: [][]const u8) u8 {
    var first = true;
    var i: usize = 1;
    while (i < args.len) {
        if (!first) _ = core.c.write(1, " ", 1);
        _ = core.c.write(1, args[i].ptr, args[i].len);
        first = false;
        i += 1;
    }
    _ = core.c.write(1, "\n", 1);
    return 0;
}
