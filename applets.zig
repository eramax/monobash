const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/utsname.h");
    @cInclude("sys/wait.h");
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("fcntl.h");
});

pub const AppletEntry = struct {
    name: []const u8,
    mainFn: *const fn (c_int, [*c][*c]u8) callconv(.c) c_int,
};

/// Write count bytes to fd from buf. Retry on EINTR.
fn writeAll(fd: c_int, buf: []const u8) void {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = c.write(fd, buf.ptr + pos, @intCast(buf.len - pos));
        if (n < 0) return;
        pos += @intCast(n);
    }
}

fn applet_cat(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    const stdout_fd: c_int = 1;
    if (argc == 1) {
        // Read from stdin
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = c.read(0, &buf, buf.len);
            if (n <= 0) break;
            writeAll(stdout_fd, buf[0..@intCast(n)]);
        }
        return 0;
    }
    var exit_code: c_int = 0;
    var i: c_int = 1;
    while (i < argc) : (i += 1) {
        const path = std.mem.sliceTo(argv[@intCast(i)], 0);
        const fd = c.open(path.ptr, c.O_RDONLY);
        if (fd < 0) { exit_code = 1; continue; }
        defer _ = c.close(fd);
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = c.read(fd, &buf, buf.len);
            if (n <= 0) break;
            writeAll(stdout_fd, buf[0..@intCast(n)]);
        }
    }
    return exit_code;
}

fn applet_true(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc; _ = argv;
    return 0;
}

fn applet_false(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc; _ = argv;
    return 1;
}

fn applet_yes(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    const out = if (argc > 1) std.mem.sliceTo(argv[1], 0) else "y";
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    while (pos + out.len + 1 < buf.len) {
        @memcpy(buf[pos..][0..out.len], out);
        pos += out.len;
        buf[pos] = '\n';
        pos += 1;
    }
    while (true) {
        writeAll(1, buf[0..pos]);
    }
    return 0;
}

fn applet_sleep(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 2) return 1;
    const s = std.mem.sliceTo(argv[1], 0);
    const secs = std.fmt.parseInt(u64, s, 10) catch return 1;
    _ = c.sleep(@intCast(secs));
    return 0;
}

fn applet_ln(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    var sym = false;
    var i: c_int = 1;
    while (i < argc and argv[@intCast(i)][0] == '-') : (i += 1) {
        const arg = std.mem.sliceTo(argv[@intCast(i)], 0);
        if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--symbolic")) sym = true;
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
    }
    if (argc - i < 2) return 1;
    const target = std.mem.sliceTo(argv[@intCast(i)], 0);
    const link_name = std.mem.sliceTo(argv[@intCast(i + 1)], 0);
    if (sym) {
        return if (c.symlink(target.ptr, link_name.ptr) == 0) 0 else 1;
    }
    return if (c.link(target.ptr, link_name.ptr) == 0) 0 else 1;
}

fn applet_chmod(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 3) return 1;
    const mode_str = std.mem.sliceTo(argv[1], 0);
    const mode = std.fmt.parseInt(u32, mode_str, 8) catch return 1;
    var i: c_int = 2;
    while (i < argc) : (i += 1) {
        const path = std.mem.sliceTo(argv[@intCast(i)], 0);
        if (c.chmod(path.ptr, @intCast(mode)) != 0) return 1;
    }
    return 0;
}

fn applet_chown(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 3) return 1;
    const owner = std.mem.sliceTo(argv[1], 0);
    // Parse uid:gid or just uid
    var uid: u32 = 0;
    var gid: u32 = std.math.maxInt(u32); // -1 = no change
    if (std.mem.indexOfScalar(u8, owner, ':')) |colon| {
        uid = std.fmt.parseInt(u32, owner[0..colon], 10) catch return 1;
        gid = if (colon + 1 < owner.len)
            (std.fmt.parseInt(u32, owner[colon + 1 ..], 10) catch return 1)
        else
            std.math.maxInt(u32);
    } else {
        uid = std.fmt.parseInt(u32, owner, 10) catch return 1;
    }
    var i: c_int = 2;
    while (i < argc) : (i += 1) {
        const path = std.mem.sliceTo(argv[@intCast(i)], 0);
        if (c.chown(path.ptr, @intCast(uid), @intCast(gid)) != 0) return 1;
    }
    return 0;
}

fn applet_uname(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    var uts: c.struct_utsname = undefined;
    if (c.uname(&uts) != 0) return 1;
    var all = argc == 1;
    var s: u8 = 0;
    var i: c_int = 1;
    while (i < argc) : (i += 1) {
        const arg = std.mem.sliceTo(argv[@intCast(i)], 0);
        if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) all = true;
        if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--kernel-name")) s = 1;
        if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--nodename")) s = 2;
        if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--kernel-release")) s = 3;
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--kernel-version")) s = 4;
        if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--machine")) s = 5;
    }
    const parts = [_][]const u8{
        std.mem.sliceTo(&uts.sysname, 0),
        std.mem.sliceTo(&uts.nodename, 0),
        std.mem.sliceTo(&uts.release, 0),
        std.mem.sliceTo(&uts.version, 0),
        std.mem.sliceTo(&uts.machine, 0),
    };
    if (all) {
        for (parts, 0..) |p, j| {
            if (j > 0) writeAll(1, " ");
            writeAll(1, p);
        }
        writeAll(1, "\n");
    } else if (s > 0) {
        writeAll(1, parts[s - 1]);
        writeAll(1, "\n");
    } else {
        writeAll(1, parts[0]);
        writeAll(1, "\n");
    }
    return 0;
}

fn applet_hostname(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argv;
    var buf: [256]u8 = undefined;
    if (c.gethostname(&buf, buf.len) != 0) return 1;
    const name = std.mem.sliceTo(&buf, 0);
    writeAll(1, name);
    if (argc == 1) writeAll(1, "\n");
    return 0;
}

extern "c" var environ: [*c][*c]u8;

fn applet_env(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc; _ = argv;
    var i: usize = 0;
    while (environ[i]) |entry| {
        const s = std.mem.sliceTo(entry, 0);
        writeAll(1, s);
        writeAll(1, "\n");
        i += 1;
    }
    return 0;
}

fn applet_printenv(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc == 1) return applet_env(argc, argv);
    var i: c_int = 1;
    while (i < argc) : (i += 1) {
        const name = std.mem.sliceTo(argv[@intCast(i)], 0);
        const val = c.getenv(name.ptr);
        if (val) |v| {
            writeAll(1, std.mem.sliceTo(v, 0));
            writeAll(1, "\n");
        } else {
            return 1;
        }
    }
    return 0;
}

fn applet_basename(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 2) return 1;
    const path = std.mem.sliceTo(argv[1], 0);
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;
    var suffix: ?[]const u8 = null;
    if (argc > 2) suffix = std.mem.sliceTo(argv[2], 0);
    const result = if (suffix) |s| blk: {
        if (std.mem.endsWith(u8, base, s))
            break :blk base[0 .. base.len - s.len];
        break :blk base;
    } else base;
    writeAll(1, result);
    writeAll(1, "\n");
    return 0;
}

fn applet_dirname(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 2) return 1;
    const path = std.mem.sliceTo(argv[1], 0);
    const dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| blk: {
        if (slash == 0) break :blk "/" else break :blk path[0..slash];
    } else ".";
    writeAll(1, dir);
    writeAll(1, "\n");
    return 0;
}

fn applet_whoami(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argv;
    if (argc > 1) return 1;
    const pw = c.getpwuid(c.getuid());
    if (pw == null) return 1;
    writeAll(1, std.mem.sliceTo(pw.*.pw_name, 0));
    writeAll(1, "\n");
    return 0;
}

fn applet_groups(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc; _ = argv;
    const gid_count = c.getgroups(0, null);
    if (gid_count < 0) return 1;
    var gid_list: [64]u32 = undefined;
    const actual = c.getgroups(@intCast(gid_count), @ptrCast(&gid_list));
    if (actual < 0) return 1;
    var buf: [256]u8 = undefined;
    var pos: usize = 0;
    var i: c_int = 0;
    while (i < actual) : (i += 1) {
        if (i > 0) { buf[pos] = ' '; pos += 1; }
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "{d}", .{gid_list[@intCast(i)]}) catch "?";
        if (pos + name.len < buf.len) {
            @memcpy(buf[pos..][0..name.len], name);
            pos += name.len;
        }
    }
    buf[pos] = '\n'; pos += 1;
    writeAll(1, buf[0..pos]);
    return 0;
}

fn applet_id(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc; _ = argv;
    const uid = c.getuid();
    const gid = c.getgid();
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "uid={d}({d}) gid={d}({d})\n", .{ uid, uid, gid, gid }) catch "?\n";
    writeAll(1, s);
    return 0;
}

fn applet_which(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc < 2) return 1;
    var found: c_int = 0;
    var i: c_int = 1;
    while (i < argc) : (i += 1) {
        const name = std.mem.sliceTo(argv[@intCast(i)], 0);

        // Check builtins (from builtins.zig lookup)
        if (builtins_lookup(name) != 0) {
            writeAll(1, name);
            writeAll(1, " (builtin)\n");
            found += 1;
            continue;
        }

        // Check applets
        if (lookup(name) != null) {
            writeAll(1, name);
            writeAll(1, " (applet)\n");
            found += 1;
            continue;
        }

        // Check PATH
        const path_env = c.getenv("PATH");
        if (path_env) |paths| {
            const path_str = std.mem.sliceTo(paths, 0);
            var it = std.mem.splitScalar(u8, path_str, ':');
            while (it.next()) |dir| {
                var buf: [4096:0]u8 = undefined;
                const path_len = (std.fmt.bufPrint(buf[0..], "{s}/{s}", .{ dir, name }) catch continue).len;
                buf[path_len] = 0;
                if (c.access(&buf, 1) == 0) { // X_OK = 1
                    writeAll(1, buf[0..path_len]);
                    writeAll(1, "\n");
                    found += 1;
                    break;
                }
            }
        }

        if (found == 0) {
            var msg: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&msg, "which: {s}: command not found\n", .{name}) catch "";
            writeAll(2, s);
        }
    }
    return if (found > 0) 0 else 1;
}

extern "c" fn builtins_lookup(name: [*c]const u8) c_int;

const applet_table: []const AppletEntry = &.{
    .{ .name = "cat",       .mainFn = applet_cat },
    .{ .name = "true",      .mainFn = applet_true },
    .{ .name = "false",     .mainFn = applet_false },
    .{ .name = "yes",       .mainFn = applet_yes },
    .{ .name = "sleep",     .mainFn = applet_sleep },
    .{ .name = "ln",        .mainFn = applet_ln },
    .{ .name = "chmod",     .mainFn = applet_chmod },
    .{ .name = "chown",     .mainFn = applet_chown },
    .{ .name = "uname",     .mainFn = applet_uname },
    .{ .name = "hostname",  .mainFn = applet_hostname },
    .{ .name = "env",       .mainFn = applet_env },
    .{ .name = "printenv",  .mainFn = applet_printenv },
    .{ .name = "basename",  .mainFn = applet_basename },
    .{ .name = "dirname",   .mainFn = applet_dirname },
    .{ .name = "whoami",    .mainFn = applet_whoami },
    .{ .name = "groups",    .mainFn = applet_groups },
    .{ .name = "id",        .mainFn = applet_id },
    .{ .name = "which",     .mainFn = applet_which },
};

pub fn lookup(name: []const u8) ?AppletEntry {
    inline for (applet_table) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}

pub fn run(io: std.Io, name: []const u8, argv: [][]const u8) u8 {
    const entry = lookup(name) orelse return 127;

    // NOEXEC: fork + call main in child
    const pid = c_fork() catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: fork failed\n", .{name}) catch "fork error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 126;
    };

    if (pid == 0) {
        // Child: build C-style argv and call applet main
        const c_argv = std.heap.page_allocator.alloc([*c]u8, argv.len + 1) catch {
            std.process.exit(126);
        };
        defer std.heap.page_allocator.free(c_argv);
        for (argv, 0..) |arg, i| {
            const arg_z = std.heap.page_allocator.dupeZ(u8, arg) catch {
                std.process.exit(126);
            };
            c_argv[i] = arg_z.ptr;
        }
        c_argv[argv.len] = null;
        const exit_code = entry.mainFn(@intCast(argv.len), c_argv.ptr);
        std.process.exit(@intCast(exit_code));
    }

    // Parent: wait for child (crash-safe: if child segfaults, parent continues)
    var wstatus: u32 = 0;
    _ = c_waitpid(pid, &wstatus, 0);
    if (c.WIFEXITED(@as(c_int, @intCast(wstatus)))) {
        return @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))));
    }
    return 1; // child crashed or was killed
}

extern "c" fn fork() c_int;
extern "c" fn waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int;

fn c_fork() !c_int {
    const pid = fork();
    if (pid < 0) return error.ForkFailed;
    return pid;
}

fn c_waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int {
    return waitpid(pid, wstatus, options);
}
