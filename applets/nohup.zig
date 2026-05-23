const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "nohup", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    _ = core.c.signal(core.c.SIGHUP, @ptrFromInt(@as(usize, 1)));
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - 1 + 1) catch return 1;
    for (args[1..], 0..) |arg, i| {
        c_argv[i] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - 1] = null;
    if (core.c.isatty(1) != 0) {
        const fd = core.c.open("nohup.out", core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND, @as(c_uint, 0o644));
        if (fd >= 0) {
            _ = core.c.dup2(fd, 1);
            _ = core.c.close(fd);
        }
    }
    if (core.c.isatty(2) != 0) {
        _ = core.c.dup2(1, 2);
    }
    const pid = core.c.fork();
    if (pid == 0) {
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }
    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 1;
}
