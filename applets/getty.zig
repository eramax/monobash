const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "getty", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: getty BAUD TTY [TERM]\n", .{});
    const alloc = std.heap.page_allocator;

    var i: usize = 1;
    const baud_str = args[i];
    i += 1;
    var tty: []const u8 = "";
    var term: []const u8 = "vt100";

    if (i < args.len) { tty = args[i]; i += 1; }
    if (i < args.len) { term = args[i]; }

    const tty_dev = if (tty.len > 0) tty else "/dev/console";
    const tty_z = alloc.dupeZ(u8, tty_dev) catch return 1;
    defer alloc.free(tty_z);

    const fd = core.c.open(tty_z.ptr, core.c.O_RDWR);
    if (fd < 0) return core.die(1, "getty: cannot open {s}\n", .{tty_dev});

    _ = core.c.setsid();
    _ = core.c.ioctl(fd, core.c.TIOCSCTTY, @as(c_int, 1));

    const baud = std.fmt.parseInt(c_uint, baud_str, 10) catch return core.die(1, "getty: bad baud\n", .{});
    var tio: core.c.struct_termios = undefined;
    _ = core.c.tcgetattr(fd, &tio);
    _ = core.c.cfsetispeed(&tio, baud);
    _ = core.c.cfsetospeed(&tio, baud);
    tio.c_cflag |= core.c.CREAD | core.c.CLOCAL | core.c.HUPCL;
    tio.c_lflag |= core.c.ICANON | core.c.ISIG | core.c.ECHO | core.c.ECHOE | core.c.ECHOK;
    _ = core.c.tcsetattr(fd, core.c.TCSANOW, &tio);

    _ = core.c.dup2(fd, 0);
    _ = core.c.dup2(fd, 1);
    _ = core.c.dup2(fd, 2);
    {
        var nfd: c_int = 3;
        while (nfd < 64) : (nfd += 1) {
            if (nfd != fd) _ = core.c.close(nfd);
        }
    }

    core.writeAll(1, "\n");
    core.writeAll(1, tty_dev);
    core.writeAll(1, " login: ");

    var buf: [256]u8 = undefined;
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = core.c.read(0, &buf[pos], 1);
        if (n <= 0) break;
        if (buf[pos] == '\n' or buf[pos] == '\r') break;
        pos += 1;
    }
    const username = std.mem.trim(u8, buf[0..pos], " \r\n");

    const login_path = "/bin/login";
    const login_z = alloc.dupeZ(u8, login_path) catch return 1;
    defer alloc.free(login_z);

    var env: [3][*:0]u8 = undefined;
    var term_var: [64]u8 = undefined;
    const tv = std.fmt.bufPrint(&term_var, "TERM={s}", .{term}) catch "TERM=vt100";
    _ = &tv;
    env[0] = @ptrCast(&term_var);
    env[1] = @ptrCast(@constCast("PATH=/sbin:/bin:/usr/sbin:/usr/bin"));
    env[2] = undefined;

    var argv: [4][*:0]u8 = undefined;
    argv[0] = @ptrCast(login_z.ptr);
    argv[1] = @ptrCast(@constCast(username.ptr));
    argv[2] = undefined;
    argv[3] = undefined;

    _ = core.c.execve(login_z.ptr, &argv, &env);
    return core.die(1, "getty: exec login failed\n", .{});
}
