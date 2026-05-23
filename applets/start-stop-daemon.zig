const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "start-stop-daemon", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    var opt_start = false;
    var opt_stop = false;
    var opt_background = false;
    var opt_quiet = false;
    var opt_test = false;
    var opt_makepid = false;
    var opt_startas: ?[]const u8 = null;
    var opt_name: ?[]const u8 = null;
    var opt_signal: ?[]const u8 = null;
    var opt_user: ?[]const u8 = null;
    var opt_chuid: ?[]const u8 = null;
    var opt_chdir: ?[]const u8 = null;
    var opt_exec: ?[]const u8 = null;
    var opt_pidfile: ?[]const u8 = null;
    var opt_output: ?[]const u8 = null;
    var opt_nice: ?i64 = null;
    var opt_oknodo = false;
    var opt_verbose = false;

    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];
        if (arg[1] == 'K' or std.mem.eql(u8, arg, "--stop")) {
            opt_stop = true;
        } else if (arg[1] == 'S' or std.mem.eql(u8, arg, "--start")) {
            opt_start = true;
        } else if (arg[1] == 'b' or std.mem.eql(u8, arg, "--background")) {
            opt_background = true;
        } else if (arg[1] == 'q' or std.mem.eql(u8, arg, "--quiet")) {
            opt_quiet = true;
        } else if (arg[1] == 't' or std.mem.eql(u8, arg, "--test")) {
            opt_test = true;
        } else if (arg[1] == 'm' or std.mem.eql(u8, arg, "--make-pidfile")) {
            opt_makepid = true;
        } else if (arg[1] == 'o' or std.mem.eql(u8, arg, "--oknodo")) {
            opt_oknodo = true;
        } else if (arg[1] == 'v' or std.mem.eql(u8, arg, "--verbose")) {
            opt_verbose = true;
        } else if (arg[1] == 'a') { i += 1; opt_startas = args[i];
        } else if (arg[1] == 'n') { i += 1; opt_name = args[i];
        } else if (arg[1] == 's') { i += 1; opt_signal = args[i];
        } else if (arg[1] == 'u') { i += 1; opt_user = args[i];
        } else if (arg[1] == 'c') { i += 1; opt_chuid = args[i];
        } else if (arg[1] == 'd') { i += 1; opt_chdir = args[i];
        } else if (arg[1] == 'x') { i += 1; opt_exec = args[i];
        } else if (arg[1] == 'p') { i += 1; opt_pidfile = args[i];
        } else if (arg[1] == 'O') { i += 1; opt_output = args[i];
        } else if (arg[1] == 'N') { i += 1; opt_nice = std.fmt.parseInt(i64, args[i], 10) catch return core.die(1, "ssd: bad nice\n", .{});
        } else if (arg[1] == 'T') { _ = 0; }
        else {
            return core.die(1, "ssd: unknown option: {s}\n", .{arg});
        }
        i += 1;
    }

    if (!opt_start and !opt_stop) return core.die(1, "usage: ssd -S|-K [OPTIONS] [-- ARGS]\n", .{});
    if (opt_start and opt_stop) return core.die(1, "ssd: -S and -K are exclusive\n", .{});

    var signal_nr: c_int = 15;
    if (opt_signal) |sig| {
        if (std.mem.eql(u8, sig, "TERM")) {
            signal_nr = 15;
        } else if (std.mem.eql(u8, sig, "HUP")) {
            signal_nr = 1;
        } else if (std.mem.eql(u8, sig, "INT")) {
            signal_nr = 2;
        } else if (std.mem.eql(u8, sig, "KILL")) {
            signal_nr = 9;
        } else if (std.mem.eql(u8, sig, "USR1")) {
            signal_nr = 10;
        } else if (std.mem.eql(u8, sig, "USR2")) {
            signal_nr = 12;
        } else {
            signal_nr = @intCast(std.fmt.parseInt(c_int, sig, 10) catch return core.die(1, "ssd: bad signal\n", .{}));
        }
    }

    var found_pids = std.ArrayListAligned(c_int, null).empty;

    if (opt_pidfile) |pf| {
        const pf_z = alloc.dupeZ(u8, pf) catch return 1;
        const f = core.c.fopen(pf_z.ptr, "r");
        if (f) |fp| {
            var line_buf: [64]u8 = undefined;
            _ = &line_buf;
            var pid: c_int = 0;
            if (core.c.fscanf(fp, "%d", &pid) >= 1) {
                found_pids.append(alloc, pid) catch {};
            }
            _ = core.c.fclose(fp);
        }
    } else {
        const proc_dir = core.c.opendir("/proc");
        if (proc_dir != null) {
            while (true) {
                const entry = core.c.readdir(proc_dir);
                if (entry == null) break;
                const d_name = &@as([*c]core.c.struct_dirent, @ptrCast(entry)).*.d_name;
                const name_slice = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(d_name)), 0);
                if (name_slice.len == 0) continue;
                const pid = std.fmt.parseInt(c_int, name_slice, 10) catch continue;
                var match = true;

                if (opt_name) |n| {
                    var stat_buf: [256]u8 = undefined;
                    const stat_path = std.fmt.bufPrint(&stat_buf, "/proc/{d}/stat", .{pid}) catch continue;
                    const stat_path_z = alloc.dupeZ(u8, stat_path) catch continue;
                    const stat_fd = core.c.open(stat_path_z.ptr, core.c.O_RDONLY);
                    if (stat_fd < 0) { match = false; } else {
                        const content = core.readAll(alloc, stat_fd, 128) catch blk: {
                            _ = core.c.close(stat_fd);
                            match = false;
                            break :blk &.{};
                        };
                        _ = core.c.close(stat_fd);
                        if (content.len > 0) {
                            if (std.mem.indexOfScalar(u8, content, '(')) |start| {
                                if (std.mem.lastIndexOfScalar(u8, content, ')')) |end| {
                                    const comm = content[start + 1 .. end];
                                    if (!std.mem.eql(u8, comm, n)) match = false;
                                } else match = false;
                            } else match = false;
                        } else match = false;
                    }
                }

                if (opt_exec) |exe| {
                    var exe_link_buf: [512]u8 = undefined;
                    const exe_path = std.fmt.bufPrint(&exe_link_buf, "/proc/{d}/exe", .{pid}) catch continue;
                    const exe_path_z = alloc.dupeZ(u8, exe_path) catch continue;
                    var link_buf: [512]u8 = undefined;
                    const r = core.c.readlink(exe_path_z.ptr, &link_buf, link_buf.len);
                    if (r < 0) { match = false; } else {
                        const link = link_buf[0..@as(usize, @intCast(r))];
                        if (!std.mem.eql(u8, link, exe)) match = false;
                    }
                }

                if (opt_user) |u| {
                    var proc_stat: core.c.struct_stat = undefined;
                    var proc_path_buf: [64]u8 = undefined;
                    const proc_path = std.fmt.bufPrint(&proc_path_buf, "/proc/{d}", .{pid}) catch continue;
                    const proc_path_z = alloc.dupeZ(u8, proc_path) catch continue;
                    if (core.c.stat(proc_path_z.ptr, &proc_stat) < 0) { match = false; } else {
                        const uid = std.fmt.parseInt(c_uint, u, 10) catch {
                            const uz = alloc.dupeZ(u8, u) catch continue;
                            const pw2 = core.c.getpwnam(uz.ptr);
                            if (pw2 == null or pw2.*.pw_uid != proc_stat.st_uid) match = false;
                            continue;
                        };
                        if (proc_stat.st_uid != uid) match = false;
                    }
                }

                if (match) found_pids.append(alloc, pid) catch {};
            }
            _ = core.c.closedir(proc_dir);
        }
    }

    if (opt_stop) {
        if (found_pids.items.len == 0) {
            if (!opt_quiet) core.writeAll(2, "no process found; none killed\n");
            return if (opt_oknodo) 0 else 1;
        }
        for (found_pids.items) |pid| {
            if (opt_test) {
                _ = core.c.kill(pid, 0);
            } else {
                _ = core.c.kill(pid, signal_nr);
            }
        }
        if (!opt_quiet and !opt_test) {
            const msg = std.fmt.allocPrint(alloc, "stopped process(es)\n", .{}) catch return 0;
            core.writeAll(1, msg);
        }
        return 0;
    }

    if (opt_start) {
        if (found_pids.items.len > 0) {
            if (!opt_quiet) {
                const msg = std.fmt.allocPrint(alloc, "{s} is already running\n", .{opt_exec orelse "process"}) catch return 0;
                core.writeAll(1, msg);
            }
            return if (opt_oknodo) 0 else 1;
        }

        var execname = opt_exec;
        var startas = opt_startas;

        if (execname == null) {
            execname = startas;
            if (execname == null) {
                if (i < args.len) {
                    execname = args[i];
                    i += 1;
                }
            }
        }
        if (startas == null) startas = execname;
        if (execname == null) return core.die(1, "ssd: no executable specified\n", .{});

        const cmdargs = if (i < args.len) args[i..] else &[_][]const u8{};

        if (opt_background) {
            const pid2 = core.c.fork();
            if (pid2 < 0) return 126;
            if (pid2 != 0) {
                var wst: c_int = 0;
                _ = core.c.waitpid(pid2, &wst, 0);
                return 0;
            }
            _ = core.c.setsid();
        }

        if (opt_nice) |n| {
            _ = core.c.setpriority(core.c.PRIO_PROCESS, 0, @intCast(n));
        }

        if (opt_chuid) |ch| {
            const alloc2 = std.heap.page_allocator;
            const ch_z = alloc2.dupeZ(u8, ch) catch return 1;
            if (core.c.getpwnam(ch_z.ptr)) |pw| {
                _ = core.c.setgid(pw.*.pw_gid);
                _ = core.c.setuid(pw.*.pw_uid);
            }
        }

        if (opt_chdir) |dir| {
            const dir_z = alloc.dupeZ(u8, dir) catch return 1;
            _ = core.c.chdir(dir_z.ptr);
        }

        if (opt_makepid) {
            if (opt_pidfile) |pf| {
                const pid_str = std.fmt.allocPrint(alloc, "{d}\n", .{core.c.getpid()}) catch return 1;
                const pf_z = alloc.dupeZ(u8, pf) catch return 1;
                const fd = core.c.open(pf_z.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
                if (fd >= 0) {
                    core.writeAll(fd, pid_str);
                    _ = core.c.close(fd);
                }
            }
        }

        if (opt_output) |out| {
            const out_z = alloc.dupeZ(u8, out) catch return 1;
            const out_fd = core.c.open(out_z.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND, @as(c_uint, 0o644));
            if (out_fd >= 0) {
                _ = core.c.dup2(out_fd, 1);
                _ = core.c.dup2(out_fd, 2);
                if (out_fd > 2) _ = core.c.close(out_fd);
            }
        }

        const execname_z = alloc.dupeZ(u8, execname.?) catch return 1;
        const startas_z = alloc.dupeZ(u8, startas.?) catch return 1;

        const total_args = 1 + cmdargs.len + 1;
        const c_argv = alloc.alloc([*c]u8, total_args) catch return 126;
        c_argv[0] = startas_z.ptr;
        for (cmdargs, 1..) |arg, j| {
            c_argv[j] = (alloc.dupeZ(u8, arg) catch return 126).ptr;
        }
        c_argv[total_args - 1] = null;

        _ = core.c.execvp(execname_z.ptr, c_argv.ptr);
        return core.die(127, "ssd: cannot execute '{s}'\n", .{execname.?});
    }

    return 0;
}
