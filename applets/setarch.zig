const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "setarch", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    _ = core.c.write(2, "setarch: unsupported, executing anyway\n", 39);
    _ = core.c.personality(core.c.ADDR_NO_RANDOMIZE);
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - 2 + 1) catch return 1;
    for (args[2..], 0..) |arg, i| {
        c_argv[i] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - 2] = null;
    _ = core.c.execvp(c_argv[0], c_argv.ptr);
    return 127;
}
