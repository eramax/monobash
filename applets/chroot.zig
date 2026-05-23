const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "chroot", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    const newroot = args[1];
    if (newroot.len >= 4096) return 1;
    var root_buf: [4096:0]u8 = undefined;
    @memcpy(root_buf[0..newroot.len], newroot);
    root_buf[newroot.len] = 0;
    if (core.c.chroot(&root_buf) != 0) return 1;
    if (core.c.chdir("/") != 0) return 1;
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - 2 + 1) catch return 1;
    for (args[2..], 0..) |arg, i| {
        c_argv[i] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - 2] = null;
    _ = core.c.execvp(c_argv[0], c_argv.ptr);
    return 127;
}
