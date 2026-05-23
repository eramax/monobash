const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "echo", .main = main };
pub fn main(args: [][]const u8) u8 {
    var first = true;
    var i: usize = 1;
    while (i < args.len) {
        if (!first) core.writeAll(1, " ");
        core.writeAll(1, args[i]);
        first = false;
        i += 1;
    }
    core.writeAll(1, "\n");
    return 0;
}
