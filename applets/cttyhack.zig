const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cttyhack", .main = main };

const TIOCSCTTY: u64 = 0x540E;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: cttyhack CMD...\n", .{});

    const pid = core.c.fork();
    if (pid < 0) return 1;

    if (pid == 0) {
        // Child process
        _ = core.c.setsid();

        // Open /dev/tty or try to find controlling TTY
        const tty = core.c.open("/dev/tty", core.c.O_RDWR);
        if (tty >= 0) {
            _ = core.c.ioctl(tty, TIOCSCTTY, @as(c_int, 0));
            // dup2 to stdin/stdout/stderr
            _ = core.c.dup2(tty, 0);
            _ = core.c.dup2(tty, 1);
            _ = core.c.dup2(tty, 2);
            if (tty > 2) _ = core.c.close(tty);
        }

        const alloc = std.heap.page_allocator;
        const argc = args.len - 1;
        const c_argv = alloc.alloc([*c]u8, argc + 1) catch core.c._exit(127);
        for (args[1..], 0..) |arg, i| {
            c_argv[i] = (alloc.dupeZ(u8, arg) catch core.c._exit(127)).ptr;
        }
        c_argv[argc] = null;

        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }

    var wstatus: c_int = 0;
    _ = core.c.waitpid(pid, &wstatus, 0);
    if (core.c.WIFEXITED(wstatus)) return @intCast(core.c.WEXITSTATUS(wstatus));
    return 1;
}
