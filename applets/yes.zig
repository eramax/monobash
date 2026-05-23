const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "yes", .main = main };

pub fn main(args: [][]const u8) u8 {
    const what = if (args.len > 1) args[1] else "y";
    while (true) {
        core.writeAll(1, what);
        core.writeAll(1, "\n");
    }
    return 0;
}
