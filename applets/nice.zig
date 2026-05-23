const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "nice", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 4 or !std.mem.eql(u8, args[1], "-n")) return 1;
    const adj = std.fmt.parseInt(i32, args[2], 10) catch return 1;
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - 3 + 1) catch return 1;
    for (args[3..], 0..) |arg, i| {
        c_argv[i] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - 3] = null;
    const pid = core.c.fork();
    if (pid == 0) {
        _ = core.c.nice(adj);
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }
    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 1;
}
