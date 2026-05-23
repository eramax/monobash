const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "sulogin", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "sulogin: not root\n", .{});

    var timeout: ?usize = null;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i][1] == 't') {
            i += 1;
            if (i >= args.len) return core.die(1, "sulogin: -t requires argument\n", .{});
            timeout = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "sulogin: bad timeout\n", .{});
        } else if (args[i][1] == 'p') {}
        i += 1;
    }

    var tty_device: ?[]const u8 = null;
    if (i < args.len) {
        tty_device = args[i];
    }

    if (tty_device) |dev| {
        const alloc = std.heap.page_allocator;
        const dev_z = alloc.dupeZ(u8, dev) catch return 1;
        const fd = core.c.open(dev_z.ptr, core.c.O_RDWR);
        if (fd >= 0) {
            _ = core.c.dup2(fd, 0);
            _ = core.c.dup2(fd, 1);
            _ = core.c.dup2(fd, 2);
            if (fd > 2) _ = core.c.close(fd);
        }
    }

    const pw = core.c.getpwuid(0);
    if (pw == null) return core.die(1, "sulogin: no password entry for root\n", .{});

    const alloc = std.heap.page_allocator;

    while (true) {
        core.writeAll(2, "Give root password for maintenance\n(or type Ctrl-D to continue): ");

        const buf = core.readAll(alloc, 0, 4096) catch return 1;
        const line = std.mem.trim(u8, buf, "\n\r ");
        if (line.len == 0) return 0;

        const sp = core.c.getspnam("root");
        if (sp == null) return core.die(1, "sulogin: no shadow entry for root\n", .{});

        const encrypted = std.mem.sliceTo(@as([*c]u8, @ptrCast(sp.*.sp_pwdp)), 0);
        const line_z = alloc.dupeZ(u8, line) catch return 1;
        const result = core.c.crypt(line_z.ptr, encrypted.ptr);
        if (result == null) return core.die(1, "sulogin: crypt failed\n", .{});

        const hash = std.mem.sliceTo(@as([*c]u8, @ptrCast(result)), 0);
        if (std.mem.eql(u8, hash, encrypted)) break;

        core.writeAll(2, "Login incorrect\n");
    }

    const shell = pw.*.pw_shell orelse @as([*c]u8, @ptrFromInt(0));
    var shell_name: []const u8 = "/bin/sh";
    if (shell != null) {
        shell_name = std.mem.sliceTo(@as([*c]u8, @ptrCast(shell)), 0);
    }

    const home = pw.*.pw_dir orelse @as([*c]u8, @ptrFromInt(0));
    var home_dir: []const u8 = "/";
    if (home != null) {
        home_dir = std.mem.sliceTo(@as([*c]u8, @ptrCast(home)), 0);
    }

    const shell_z = alloc.dupeZ(u8, shell_name) catch return 1;

    const tsid = core.c.tcgetsid(0);
    if (tsid < 0 or core.c.getpid() != tsid) {
        _ = core.c.ioctl(0, core.c.TIOCSCTTY, @as(c_long, 1));
        if (core.c.setsid() > 0) {
            _ = core.c.ioctl(0, core.c.TIOCSCTTY, @as(c_long, 1));
        }
    }

    var args_buf: [2][*c]u8 = .{ shell_z.ptr, null };
    _ = core.c.execvp(shell_z.ptr, &args_buf);
    _ = core.c.execvp("/bin/sh", &args_buf);
    return 1;
}
