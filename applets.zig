const std = @import("std");
const core = @import("applets/core.zig");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/wait.h");
});

// Import all applet modules — add new applets here
const applets = struct {
    const _true = @import("applets/true.zig");
    const _false = @import("applets/false.zig");
    const _cat = @import("applets/cat.zig");
    const _yes = @import("applets/yes.zig");
    const _sleep = @import("applets/sleep.zig");
    const _ln = @import("applets/ln.zig");
    const _chmod = @import("applets/chmod.zig");
    const _chown = @import("applets/chown.zig");
    const _uname = @import("applets/uname.zig");
    const _hostname = @import("applets/hostname.zig");
    const _env = @import("applets/env.zig");
    const _printenv = @import("applets/printenv.zig");
    const _basename = @import("applets/basename.zig");
    const _dirname = @import("applets/dirname.zig");
    const _whoami = @import("applets/whoami.zig");
    const _id = @import("applets/id.zig");
    const _which = @import("applets/which.zig");
    const _grep = @import("applets/grep.zig");
    const _groups = @import("applets/groups.zig");
    const _head = @import("applets/head.zig");
    const _tail = @import("applets/tail.zig");
    const _wc = @import("applets/wc.zig");
    const _uniq = @import("applets/uniq.zig");
    const _cut = @import("applets/cut.zig");
    const _tr = @import("applets/tr.zig");
    const _tee = @import("applets/tee.zig");
    const _seq = @import("applets/seq.zig");
    const _arch = @import("applets/arch.zig");
    const _nproc = @import("applets/nproc.zig");
    const _uptime = @import("applets/uptime.zig");
    const _users = @import("applets/users.zig");
    const _date = @import("applets/date.zig");
    const _echo = @import("applets/echo.zig");
    const _test = @import("applets/test.zig");
    const _clear = @import("applets/clear.zig");
    const _cp = @import("applets/cp.zig");
    const _mv = @import("applets/mv.zig");
    const _rm = @import("applets/rm.zig");
    const _mkdir = @import("applets/mkdir.zig");
    const _rmdir = @import("applets/rmdir.zig");
    const _touch = @import("applets/touch.zig");
};

fn Wrapper(comptime meta: core.AppletMeta) core.AppletEntry {
    const T = struct {
        fn call(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
            const alloc = std.heap.page_allocator;
            const args = alloc.alloc([]const u8, @intCast(argc)) catch return 127;
            defer alloc.free(args);
            for (0..@intCast(argc)) |i| args[i] = std.mem.sliceTo(argv[i], 0);
            return @intCast(meta.main(args));
        }
    };
    return .{ .name = meta.name, .mainFn = T.call };
}

// List all applet metas here — add new applets here too
const all_metas = &[_]core.AppletMeta{
    applets._true.meta,
    applets._false.meta,
    applets._cat.meta,
    applets._yes.meta,
    applets._sleep.meta,
    applets._ln.meta,
    applets._chmod.meta,
    applets._chown.meta,
    applets._uname.meta,
    applets._hostname.meta,
    applets._env.meta,
    applets._printenv.meta,
    applets._basename.meta,
    applets._dirname.meta,
    applets._whoami.meta,
    applets._id.meta,
    applets._which.meta,
    applets._grep.meta,
    applets._groups.meta,
    applets._head.meta,
    applets._tail.meta,
    applets._wc.meta,
    applets._uniq.meta,
    applets._cut.meta,
    applets._tr.meta,
    applets._tee.meta,
    applets._seq.meta,
    applets._arch.meta,
    applets._nproc.meta,
    applets._uptime.meta,
    applets._users.meta,
    applets._date.meta,
    applets._echo.meta,
    applets._test.meta,
    applets._clear.meta,
    applets._cp.meta,
    applets._mv.meta,
    applets._rm.meta,
    applets._mkdir.meta,
    applets._rmdir.meta,
    applets._touch.meta,
};

pub fn lookup(name: []const u8) ?core.AppletEntry {
    inline for (all_metas) |meta| {
        if (std.mem.eql(u8, name, meta.name)) {
            return Wrapper(meta);
        }
    }
    return null;
}

pub fn run(io: std.Io, name: []const u8, argv: [][]const u8) u8 {
    const entry = lookup(name) orelse return 127;

    const pid = c_fork() catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: fork failed\n", .{name}) catch "fork error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 126;
    };

    if (pid == 0) {
        const c_argv = std.heap.page_allocator.alloc([*c]u8, argv.len + 1) catch std.process.exit(126);
        defer std.heap.page_allocator.free(c_argv);
        for (argv, 0..) |arg, i| {
            const arg_z = std.heap.page_allocator.dupeZ(u8, arg) catch std.process.exit(126);
            c_argv[i] = arg_z.ptr;
        }
        c_argv[argv.len] = null;
        std.process.exit(@intCast(entry.mainFn(@intCast(argv.len), c_argv.ptr)));
    }

    var wstatus: u32 = 0;
    _ = c_waitpid(pid, &wstatus, 0);
    if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
        return @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))));
    return 1;
}

extern "c" fn fork() c_int;
extern "c" fn waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int;

fn c_fork() !c_int {
    const pid = fork();
    return if (pid < 0) error.ForkFailed else pid;
}

fn c_waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int {
    return waitpid(pid, wstatus, options);
}
