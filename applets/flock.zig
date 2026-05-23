const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "flock", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    const file = args[1];
    if (file.len >= 4096) return 1;
    var path_buf: [4096:0]u8 = undefined;
    @memcpy(path_buf[0..file.len], file);
    path_buf[file.len] = 0;
    const fd = core.c.open(&path_buf, core.c.O_RDWR | core.c.O_CREAT, @as(c_uint, 0o644));
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    if (core.c.flock(fd, core.c.LOCK_EX) != 0) return 1;
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - 2 + 1) catch return 1;
    for (args[2..], 0..) |arg, i| {
        c_argv[i] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - 2] = null;
    const pid = core.c.fork();
    if (pid == 0) {
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }
    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    _ = core.c.flock(fd, core.c.LOCK_UN);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 1;
}
