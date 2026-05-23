const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "timeout", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    const secs = std.fmt.parseUnsigned(u31, args[1], 10) catch return 1;
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
    var rem: u31 = secs;
    while (rem > 0) {
        const unslept = core.c.sleep(rem);
        rem = @intCast(unslept);
        var st: c_int = 0;
        const ret = core.c.waitpid(pid, &st, core.c.WNOHANG);
        if (ret == pid) {
            if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
            return 1;
        }
    }
    _ = core.c.kill(pid, core.c.SIGKILL);
    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 124;
}
