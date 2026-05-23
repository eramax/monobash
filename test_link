const std = @import("std");
const core = @import("applets/core.zig");
const c = @import("cimport.zig").c;

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
    const _sort = @import("applets/sort.zig");
    const _sed = @import("applets/sed.zig");
    const _strings = @import("applets/strings.zig");
    const _tac = @import("applets/tac.zig");
    const _split = @import("applets/split.zig");
    const _diff = @import("applets/diff.zig");
    const _more = @import("applets/more.zig");
    const _less = @import("applets/less.zig");
    const _ps = @import("applets/ps.zig");
    const _top = @import("applets/top.zig");
    const _mount = @import("applets/mount.zig");
    const _stat = @import("applets/stat.zig");
    const _du = @import("applets/du.zig");
    const _df = @import("applets/df.zig");
    const _xargs = @import("applets/xargs.zig");
    const _bc = @import("applets/bc.zig");
    const _ls = @import("applets/ls.zig");
    const _find = @import("applets/find.zig");
    const _tar = @import("applets/tar.zig");
    const _gzip = @import("applets/gzip.zig");
    const _dd = @import("applets/dd.zig");
    const _timeout = @import("applets/timeout.zig");
    const _nice = @import("applets/nice.zig");
    const _nohup = @import("applets/nohup.zig");
    const _stdbuf = @import("applets/stdbuf.zig");
    const _renice = @import("applets/renice.zig");
    const _ionice = @import("applets/ionice.zig");
    const _chrt = @import("applets/chrt.zig");
    const _setsid = @import("applets/setsid.zig");
    const _setarch = @import("applets/setarch.zig");
    const _chroot = @import("applets/chroot.zig");
    const _flock = @import("applets/flock.zig");
    const _realpath = @import("applets/realpath.zig");
    const _readlink = @import("applets/readlink.zig");
    const _link = @import("applets/link.zig");
    const _mkfifo = @import("applets/mkfifo.zig");
    const _truncate = @import("applets/truncate.zig");
    const _shred = @import("applets/shred.zig");
    const _logname = @import("applets/logname.zig");
    const _pinky = @import("applets/pinky.zig");
    const _who = @import("applets/who.zig");
    const _dmesg = @import("applets/dmesg.zig");
    const _logger = @import("applets/logger.zig");
    const _mesg = @import("applets/mesg.zig");
    const _wall = @import("applets/wall.zig");
    const _write = @import("applets/write.zig");
    const _comm = @import("applets/comm.zig");
    const _expand = @import("applets/expand.zig");
    const _fmt = @import("applets/fmt.zig");
    const _fold = @import("applets/fold.zig");
    const _join = @import("applets/join.zig");
    const _nl = @import("applets/nl.zig");
    const _od = @import("applets/od.zig");
    const _paste = @import("applets/paste.zig");
    const _pr = @import("applets/pr.zig");
    const _unexpand = @import("applets/unexpand.zig");
    const _shuf = @import("applets/shuf.zig");
    const _factor = @import("applets/factor.zig");
    const _sum = @import("applets/sum.zig");
    const _cksum = @import("applets/cksum.zig");
    const _md5sum = @import("applets/md5sum.zig");
    const _base32 = @import("applets/base32.zig");
    const _base64 = @import("applets/base64.zig");
    const _numfmt = @import("applets/numfmt.zig");
    const _tsort = @import("applets/tsort.zig");
    const _expr = @import("applets/expr.zig");
    const _unlink = @import("applets/unlink.zig");
    const _sync = @import("applets/sync.zig");
    const _tty = @import("applets/tty.zig");
    const _mktemp = @import("applets/mktemp.zig");
    const _basenc = @import("applets/basenc.zig");
    const _csplit = @import("applets/csplit.zig");
    const _hostid = @import("applets/hostid.zig");
    const _pathchk = @import("applets/pathchk.zig");
    const _stty = @import("applets/stty.zig");
    const _install = @import("applets/install.zig");
    const _dircolors = @import("applets/dircolors.zig");
    const _chcon = @import("applets/chcon.zig");
    const _runcon = @import("applets/runcon.zig");
    const _ptx = @import("applets/ptx.zig");
    const _mknod = @import("applets/mknod.zig");
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
    applets._sort.meta,
    applets._sed.meta,
    applets._strings.meta,
    applets._tac.meta,
    applets._split.meta,
    applets._diff.meta,
    applets._more.meta,
    applets._less.meta,
    applets._ps.meta,
    applets._top.meta,
    applets._mount.meta,
    applets._stat.meta,
    applets._du.meta,
    applets._df.meta,
    applets._xargs.meta,
    applets._bc.meta,
    applets._ls.meta,
    applets._find.meta,
    applets._tar.meta,
    applets._gzip.meta,
    applets._dd.meta,
    applets._timeout.meta,
    applets._nice.meta,
    applets._nohup.meta,
    applets._stdbuf.meta,
    applets._renice.meta,
    applets._ionice.meta,
    applets._chrt.meta,
    applets._setsid.meta,
    applets._setarch.meta,
    applets._chroot.meta,
    applets._flock.meta,
    applets._realpath.meta,
    applets._readlink.meta,
    applets._link.meta,
    applets._mkfifo.meta,
    applets._truncate.meta,
    applets._shred.meta,
    applets._logname.meta,
    applets._pinky.meta,
    applets._who.meta,
    applets._dmesg.meta,
    applets._logger.meta,
    applets._mesg.meta,
    applets._wall.meta,
    applets._write.meta,
    applets._comm.meta,
    applets._expand.meta,
    applets._fmt.meta,
    applets._fold.meta,
    applets._join.meta,
    applets._nl.meta,
    applets._od.meta,
    applets._paste.meta,
    applets._pr.meta,
    applets._unexpand.meta,
    applets._shuf.meta,
    applets._factor.meta,
    applets._sum.meta,
    applets._cksum.meta,
    applets._md5sum.meta,
    applets._base32.meta,
    applets._base64.meta,
    applets._numfmt.meta,
    applets._tsort.meta,
    applets._expr.meta,
    applets._unlink.meta,
    applets._sync.meta,
    applets._tty.meta,
    applets._mktemp.meta,
    applets._basenc.meta,
    applets._csplit.meta,
    applets._hostid.meta,
    applets._pathchk.meta,
    applets._stty.meta,
    applets._install.meta,
    applets._dircolors.meta,
    applets._chcon.meta,
    applets._runcon.meta,
    applets._ptx.meta,
    applets._mknod.meta,
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
