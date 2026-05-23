const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "pgrep", .main = main };

const alloc = std.heap.page_allocator;

fn readProcFile(pid: usize, sub: []const u8) ?[]u8 {
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/{s}", .{ pid, sub }) catch return null;
    var z_buf: [256:0]u8 = undefined;
    if (path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(&z_buf, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 4096) catch null;
}

fn getField(data: []const u8, field: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[i..], '\n') orelse data.len;
        const line = data[i .. i + nl];
        i += nl + 1;
        if (std.mem.startsWith(u8, line, field)) {
            return std.mem.trim(u8, line[field.len..], " \t");
        }
    }
    return null;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: pgrep [-flax] [-u USER] PATTERN\n", .{});

    var i: usize = 1;
    var opt_full = false;
    var opt_list = false;
    var opt_all = false;
    var opt_exact = false;
    var opt_user: ?[]const u8 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) {
            i += 1;
            break;
        }
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-u")) {
            i += 1;
            if (i >= args.len) return core.die(1, "pgrep: -u requires argument\n", .{});
            opt_user = args[i];
            i += 1;
            continue;
        }
        for (arg[1..]) |c| {
            switch (c) {
                'f' => opt_full = true,
                'l' => opt_list = true,
                'a' => opt_all = true,
                'x' => opt_exact = true,
                else => return core.die(1, "pgrep: unknown option -{c}\n", .{c}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "pgrep: no pattern\n", .{});
    const pattern = args[i];

    var uid_filter: ?u32 = null;
    if (opt_user) |u| {
        const u_z = alloc.dupeZ(u8, u) catch return 1;
        defer alloc.free(u_z);
        const pw = core.c.getpwnam(u_z.ptr);
        if (pw == null) return core.die(1, "pgrep: unknown user '{s}'\n", .{u});
        uid_filter = pw.*.pw_uid;
    }

    const proc_dir = core.c.opendir("/proc");
    if (proc_dir == null) return 1;
    defer _ = core.c.closedir(proc_dir);

    var matched = false;

    while (true) {
        const entry = core.c.readdir(proc_dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        const pid = std.fmt.parseUnsigned(usize, name, 10) catch continue;

        const status_data = readProcFile(pid, "status") orelse continue;
        defer alloc.free(status_data);

        if (uid_filter) |uid| {
            const uid_str = getField(status_data, "Uid:") orelse continue;
            var it = std.mem.tokenizeScalar(u8, uid_str, ' ');
            const puid = std.fmt.parseUnsigned(u32, it.next() orelse continue, 10) catch continue;
            if (puid != uid) continue;
        }

        const entry_name = if (opt_full) blk: {
            const cmdline = readProcFile(pid, "cmdline") orelse continue;
            const clean = std.mem.trimEnd(u8, cmdline, "\n");
            break :blk clean;
        } else getField(status_data, "Name:") orelse continue;

        const matched_p = if (opt_exact)
            std.mem.eql(u8, entry_name, pattern)
        else
            std.mem.indexOf(u8, entry_name, pattern) != null;

        if (matched_p) {
            matched = true;
            var out: [2048]u8 = undefined;
            if (opt_all) {
                const cmdline = readProcFile(pid, "cmdline") orelse continue;
                defer alloc.free(cmdline);
                const line = std.fmt.bufPrint(&out, "{d} {s}\n", .{ pid, cmdline }) catch continue;
                core.writeAll(1, line);
            } else if (opt_list) {
                const line = std.fmt.bufPrint(&out, "{d} {s}\n", .{ pid, entry_name }) catch continue;
                core.writeAll(1, line);
            } else {
                const line = std.fmt.bufPrint(&out, "{d}\n", .{pid}) catch continue;
                core.writeAll(1, line);
            }
        }

        if (opt_full) alloc.free(entry_name);
    }

    return if (matched) 0 else 1;
}
