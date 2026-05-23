const std = @import("std");
const core = @import("core.zig");
const VT_OPENQRY: u32 = 0x5609;
const VT_ACTIVATE: u32 = 0x5606;
const VT_WAITACTIVE: u32 = 0x5607;
const VT_GETSTATE: u32 = 0x5603;
pub const meta = core.AppletMeta{ .name = "openvt", .main = main };
fn findFreeVtno() ?u32 {
    var vtno: c_int = 0;
    const fd = core.c.open("/dev/console", core.c.O_RDONLY | core.c.O_NONBLOCK);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    if (core.c.ioctl(fd, VT_OPENQRY, &vtno) < 0 or vtno <= 0) return null;
    return @intCast(vtno);
}
fn makePath(comptime fmt: []const u8, args: anytype) [:0]u8 {
    var buf: [64:0]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch "???";
    buf[s.len] = 0;
    return buf[0..s.len :0];
}
pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var vtno: u32 = 0;
    var opt_switch: bool = false;
    var opt_wait: bool = false;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-c") and i + 1 < args.len) {
            i += 1;
            vtno = std.fmt.parseInt(u32, args[i], 10) catch return core.die(1, "openvt: bad VT number\n", .{});
            if (vtno < 1 or vtno > 63) return core.die(1, "openvt: VT number must be 1-63\n", .{});
        } else if (std.mem.eql(u8, args[i], "-s")) {
            opt_switch = true;
        } else if (std.mem.eql(u8, args[i], "-w")) {
            opt_wait = true;
        } else if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            break;
        } else if (args[i][0] == '-') {
            return core.die(1, "usage: openvt [-c N] [-sw] [PROG ARGS]\n", .{});
        } else {
            break;
        }
        i += 1;
    }
    if (vtno == 0) {
        vtno = findFreeVtno() orelse return core.die(1, "openvt: cannot find free VT\n", .{});
    }
    _ = core.c.close(core.c.STDIN_FILENO);
    const vtname = makePath("/dev/tty{d}", .{vtno});
    const new_fd = core.c.open(vtname.ptr, core.c.O_RDWR);
    if (new_fd < 0) return core.die(1, "openvt: cannot open /dev/tty{d}\n", .{vtno});
    var old_vtstat: [6]u8 = undefined;
    if (core.c.ioctl(core.c.STDIN_FILENO, VT_GETSTATE, &old_vtstat) < 0) {}
    if (opt_switch) {
        if (core.c.ioctl(core.c.STDIN_FILENO, VT_ACTIVATE, vtno) < 0 or
            core.c.ioctl(core.c.STDIN_FILENO, VT_WAITACTIVE, vtno) < 0)
            return core.die(1, "openvt: switch VT failed\n", .{});
    }
    const prog_args = args[i..];
    const alloc = std.heap.page_allocator;
    var argv_list = std.ArrayListUnmanaged([*c]u8).empty;
    defer argv_list.deinit(alloc);
    if (prog_args.len == 0) {
        const shell_env = core.c.getenv("SHELL");
        const shell = shell_env orelse @as([*:0]u8, @constCast(@as([*:0]const u8, "/bin/sh")));
        argv_list.append(alloc, shell) catch return 1;
        argv_list.append(alloc, null) catch return 1;
    } else {
        for (prog_args) |arg| {
            const z = alloc.dupeZ(u8, arg) catch return 1;
            argv_list.append(alloc, @as([*c]u8, @ptrCast(z.ptr))) catch return 1;
        }
        argv_list.append(alloc, null) catch return 1;
    }
    const pid = core.c.fork();
    if (pid < 0) return core.die(1, "openvt: fork failed\n", .{});
    if (pid == 0) {
        _ = core.c.setsid();
        _ = core.c.ioctl(core.c.STDIN_FILENO, core.c.TIOCSCTTY, @as(c_ulong, 0));
        _ = core.c.dup2(core.c.STDIN_FILENO, core.c.STDOUT_FILENO);
        _ = core.c.dup2(core.c.STDIN_FILENO, core.c.STDERR_FILENO);
        _ = core.c.execvp(argv_list.items[0], argv_list.items.ptr);
        core.c._exit(127);
    }
    if (opt_wait) {
        var status: c_int = 0;
        while (core.c.waitpid(pid, &status, 0) < 0) {}
    }
    return 0;
}
