const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "runcon", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: runcon CONTEXT CMD [ARGS]...\n", .{});
    const cmd = args[2];
    var argv_buf: [32][4096:0]u8 = undefined;
    var c_argv: [33][*c]u8 = undefined;
    var ac: usize = 0;
    var j: usize = 2;
    while (j < args.len and ac < argv_buf.len) : (j += 1) {
        const arg = args[j];
        if (arg.len >= argv_buf[ac].len) return 1;
        @memcpy(argv_buf[ac][0..arg.len], arg);
        argv_buf[ac][arg.len] = 0;
        c_argv[ac] = &argv_buf[ac];
        ac += 1;
    }
    c_argv[ac] = null;
    core.writeAll(2, "runcon: SELinux not available, executing directly\n");
    _ = core.c.execvp(@as([*c]const u8, @ptrCast(&c_argv[0])), &c_argv);
    core.eprint("runcon: cannot execute '{s}'\n", .{cmd});
    return 1;
}
