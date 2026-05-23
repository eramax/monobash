const std = @import("std");
const core = @import("applets/core.zig");
const c = @import("cimport.zig").c;

// Import all applet modules — add new applets here
const applets = struct {
    const _zip = @import("applets/zip.zig");
    const _zcat = @import("applets/zcat.zig");
    const _unzip = @import("applets/unzip.zig");
    const _rpm2cpio = @import("applets/rpm2cpio.zig");
    const _cpio = @import("applets/cpio.zig");
    const _compress = @import("applets/compress.zig");
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
    const _crond = @import("applets/crond.zig");
    const _crontab = @import("applets/crontab.zig");
    const _syslogd = @import("applets/syslogd.zig");
    const _kill = @import("applets/kill.zig");
    const _passwd = @import("applets/passwd.zig");
    const _adduser = @import("applets/adduser.zig");
    const _addgroup = @import("applets/addgroup.zig");
    const _su = @import("applets/su.zig");
    const _login = @import("applets/login.zig");
    const _reboot = @import("applets/reboot.zig");
    const _halt = @import("applets/halt.zig");
    const _poweroff = @import("applets/poweroff.zig");
    const _init = @import("applets/init.zig");
    const _modprobe = @import("applets/modprobe.zig");
    const _modinfo = @import("applets/modinfo.zig");
    const _ping = @import("applets/ping.zig");
    const _ifconfig = @import("applets/ifconfig.zig");
    const _nc = @import("applets/nc.zig");
    const _nslookup = @import("applets/nslookup.zig");
    const _wget = @import("applets/wget.zig");
    const _route = @import("applets/route.zig");
    const _arp = @import("applets/arp.zig");
    const _ftp = @import("applets/ftp.zig");
    const _cmp = @import("applets/cmp.zig");
    const _hexdump = @import("applets/hexdump.zig");
    const _rev = @import("applets/rev.zig");
    const _cal = @import("applets/cal.zig");
    const _dc = @import("applets/dc.zig");
    const _watch = @import("applets/watch.zig");
    const _tree = @import("applets/tree.zig");
    const _vi = @import("applets/vi.zig");
    const _patch = @import("applets/patch.zig");
    const _awk = @import("applets/awk.zig");
    const _arping = @import("applets/arping.zig");
    const _ftpd = @import("applets/ftpd.zig");
    const _httpd = @import("applets/httpd.zig");
    const _ip = @import("applets/ip.zig");
    const _netstat = @import("applets/netstat.zig");
    const _ntpd = @import("applets/ntpd.zig");
    const _telnet = @import("applets/telnet.zig");
    const _tftp = @import("applets/tftp.zig");
    const _traceroute = @import("applets/traceroute.zig");
    // --- Batch 6: Networking ---
    const _brctl = @import("applets/brctl.zig");
    const _chat = @import("applets/chat.zig");
    const _dhcprelay = @import("applets/dhcprelay.zig");
    const _dnsd = @import("applets/dnsd.zig");
    const _dnsdomainname = @import("applets/dnsdomainname.zig");
    const _ftpget = @import("applets/ftpget.zig");
    const _ftpput = @import("applets/ftpput.zig");
    const _getty = @import("applets/getty.zig");
    const _ifenslave = @import("applets/ifenslave.zig");
    const _ifplugd = @import("applets/ifplugd.zig");
    const _inetd = @import("applets/inetd.zig");
    const _ipaddr = @import("applets/ipaddr.zig");
    const _ipcalc = @import("applets/ipcalc.zig");
    const _ipcrm = @import("applets/ipcrm.zig");
    const _ipcs = @import("applets/ipcs.zig");
    const _iplink = @import("applets/iplink.zig");
    const _ipneigh = @import("applets/ipneigh.zig");
    const _iproute = @import("applets/iproute.zig");
    const _iprule = @import("applets/iprule.zig");
    const _iptunnel = @import("applets/iptunnel.zig");
    const _lpd = @import("applets/lpd.zig");
    const _lpq = @import("applets/lpq.zig");
    const _lpr = @import("applets/lpr.zig");
    const _nameif = @import("applets/nameif.zig");
    const _nbd_client = @import("applets/nbd-client.zig");
    const _ping6 = @import("applets/ping6.zig");
    const _popmaildir = @import("applets/popmaildir.zig");
    const _pscan = @import("applets/pscan.zig");
    const _rdate = @import("applets/rdate.zig");
    const _sendmail = @import("applets/sendmail.zig");
    const _slattach = @import("applets/slattach.zig");
    const _ssl_client = @import("applets/ssl_client.zig");
    const _tcpsvd = @import("applets/tcpsvd.zig");
    const _telnetd = @import("applets/telnetd.zig");
    const _tftpd = @import("applets/tftpd.zig");
    const _traceroute6 = @import("applets/traceroute6.zig");
    const _udhcpc = @import("applets/udhcpc.zig");
    const _udhcpd = @import("applets/udhcpd.zig");
    const _udpsvd = @import("applets/udpsvd.zig");
    const _zcip = @import("applets/zcip.zig");
    // --- Batch 6: Process/Signal ---
    const _killall = @import("applets/killall.zig");
    const _killall5 = @import("applets/killall5.zig");
    const _pkill = @import("applets/pkill.zig");
    const _powertop = @import("applets/powertop.zig");
    const _runlevel = @import("applets/runlevel.zig");
    const _runsv = @import("applets/runsv.zig");
    const _runsvdir = @import("applets/runsvdir.zig");
    const _svc = @import("applets/svc.zig");
    const _svlogd = @import("applets/svlogd.zig");
    const _time = @import("applets/time.zig");
    const _usleep = @import("applets/usleep.zig");
    const _w = @import("applets/w.zig");
    const _watchdog = @import("applets/watchdog.zig");
    // --- Batch 6: Security/Auth ---
    const _add_shell = @import("applets/add-shell.zig");
    const _chpasswd = @import("applets/chpasswd.zig");
    const _cryptpw = @import("applets/cryptpw.zig");
    const _delgroup = @import("applets/delgroup.zig");
    const _deluser = @import("applets/deluser.zig");
    const _envuidgid = @import("applets/envuidgid.zig");
    const _mkpasswd = @import("applets/mkpasswd.zig");
    const _remove_shell = @import("applets/remove-shell.zig");
    const _setpriv = @import("applets/setpriv.zig");
    const _setserial = @import("applets/setserial.zig");
    const _setuidgid = @import("applets/setuidgid.zig");
    const _softlimit = @import("applets/softlimit.zig");
    const _start_stop_daemon = @import("applets/start-stop-daemon.zig");
    const _sulogin = @import("applets/sulogin.zig");
    // --- Batch 6: Display/Terminal ---
    const _beep = @import("applets/beep.zig");
    const _chvt = @import("applets/chvt.zig");
    const _deallocvt = @import("applets/deallocvt.zig");
    const _dumpkmap = @import("applets/dumpkmap.zig");
    const _fgconsole = @import("applets/fgconsole.zig");
    const _kbd_mode = @import("applets/kbd_mode.zig");
    const _loadfont = @import("applets/loadfont.zig");
    const _loadkmap = @import("applets/loadkmap.zig");
    const _openvt = @import("applets/openvt.zig");
    const _setconsole = @import("applets/setconsole.zig");
    const _setfont = @import("applets/setfont.zig");
    const _setkeycodes = @import("applets/setkeycodes.zig");
    const _setlogcons = @import("applets/setlogcons.zig");
    const _showkey = @import("applets/showkey.zig");
    const _ttysize = @import("applets/ttysize.zig");
    // --- Compression (WIP — needs Zig 0.16 API migration) ---
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
    applets._crond.meta,
    applets._crontab.meta,
    applets._syslogd.meta,
    applets._kill.meta,
    applets._passwd.meta,
    applets._adduser.meta,
    applets._addgroup.meta,
    applets._su.meta,
    applets._login.meta,
    applets._reboot.meta,
    applets._halt.meta,
    applets._poweroff.meta,
    applets._init.meta,
    applets._modprobe.meta,
    applets._modinfo.meta,
    applets._ping.meta,
    applets._ifconfig.meta,
    applets._nc.meta,
    applets._nslookup.meta,
    applets._wget.meta,
    applets._route.meta,
    applets._arp.meta,
    applets._ftp.meta,
    applets._compress.meta,
    applets._cpio.meta,
    applets._rpm2cpio.meta,
    applets._unzip.meta,
    applets._zcat.meta,
    applets._zip.meta,
    applets._cmp.meta,
    applets._hexdump.meta,
    applets._rev.meta,
    applets._cal.meta,
    applets._dc.meta,
    applets._watch.meta,
    applets._tree.meta,
    applets._vi.meta,
    applets._patch.meta,
    applets._awk.meta,
    applets._arping.meta,
    applets._ftpd.meta,
    applets._httpd.meta,
    applets._ip.meta,
    applets._netstat.meta,
    applets._ntpd.meta,
    applets._telnet.meta,
    applets._tftp.meta,
    applets._traceroute.meta,
    // --- Batch 6: Networking ---
    applets._brctl.meta,
    applets._chat.meta,
    applets._dhcprelay.meta,
    applets._dnsd.meta,
    applets._dnsdomainname.meta,
    applets._ftpget.meta,
    applets._ftpput.meta,
    applets._getty.meta,
    applets._ifenslave.meta,
    applets._ifplugd.meta,
    applets._inetd.meta,
    applets._ipaddr.meta,
    applets._ipcalc.meta,
    applets._ipcrm.meta,
    applets._ipcs.meta,
    applets._iplink.meta,
    applets._ipneigh.meta,
    applets._iproute.meta,
    applets._iprule.meta,
    applets._iptunnel.meta,
    applets._lpd.meta,
    applets._lpq.meta,
    applets._lpr.meta,
    applets._nameif.meta,
    applets._nbd_client.meta,
    applets._ping6.meta,
    applets._popmaildir.meta,
    applets._pscan.meta,
    applets._rdate.meta,
    applets._sendmail.meta,
    applets._slattach.meta,
    applets._ssl_client.meta,
    applets._tcpsvd.meta,
    applets._telnetd.meta,
    applets._tftpd.meta,
    applets._traceroute6.meta,
    applets._udhcpc.meta,
    applets._udhcpd.meta,
    applets._udpsvd.meta,
    applets._zcip.meta,
    // --- Batch 6: Process/Signal ---
    applets._killall.meta,
    applets._killall5.meta,
    applets._pkill.meta,
    applets._powertop.meta,
    applets._runlevel.meta,
    applets._runsv.meta,
    applets._runsvdir.meta,
    applets._svc.meta,
    applets._svlogd.meta,
    applets._time.meta,
    applets._usleep.meta,
    applets._w.meta,
    applets._watchdog.meta,
    // --- Batch 6: Security/Auth ---
    applets._add_shell.meta,
    applets._chpasswd.meta,
    applets._cryptpw.meta,
    applets._delgroup.meta,
    applets._deluser.meta,
    applets._envuidgid.meta,
    applets._mkpasswd.meta,
    applets._remove_shell.meta,
    applets._setpriv.meta,
    applets._setserial.meta,
    applets._setuidgid.meta,
    applets._softlimit.meta,
    applets._start_stop_daemon.meta,
    applets._sulogin.meta,
    // --- Batch 6: Display/Terminal ---
    applets._beep.meta,
    applets._chvt.meta,
    applets._deallocvt.meta,
    applets._dumpkmap.meta,
    applets._fgconsole.meta,
    applets._kbd_mode.meta,
    applets._loadfont.meta,
    applets._loadkmap.meta,
    applets._openvt.meta,
    applets._setconsole.meta,
    applets._setfont.meta,
    applets._setkeycodes.meta,
    applets._setlogcons.meta,
    applets._showkey.meta,
    applets._ttysize.meta,
    // --- Compression (WIP) ---
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
        // Child process: disable io_uring to avoid corrupting the parent's ring
        core.iouring_mode = false;
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
