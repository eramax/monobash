const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "stdbuf", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    var cmd_start: usize = 1;
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.startsWith(u8, args[i], "-")) {
            if (args[i].len < 3) return 1;
            const stream = args[i][1];
            const mode = args[i][2];
            if (stream == 'o') {
                if (mode == 'L') {
                    _ = core.c.setvbuf(core.c.stdout, null, core.c._IOLBF, 0);
                } else if (mode == '0') {
                    _ = core.c.setvbuf(core.c.stdout, null, core.c._IONBF, 0);
                } else return 1;
            } else if (stream == 'e') {
                if (mode == 'L') {
                    _ = core.c.setvbuf(core.c.stderr, null, core.c._IOLBF, 0);
                } else if (mode == '0') {
                    _ = core.c.setvbuf(core.c.stderr, null, core.c._IONBF, 0);
                } else return 1;
            } else return 1;
            cmd_start = i + 1;
        } else break;
        i += 1;
    }
    if (cmd_start >= args.len) return 1;
    const alloc = std.heap.page_allocator;
    const c_argv = alloc.alloc([*c]u8, args.len - cmd_start + 1) catch return 1;
    for (args[cmd_start..], 0..) |arg, j| {
        c_argv[j] = (alloc.dupeZ(u8, arg) catch return 1).ptr;
    }
    c_argv[args.len - cmd_start] = null;
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
