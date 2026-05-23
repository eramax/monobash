const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "fuser", .main = main };

const alloc = std.heap.page_allocator;

fn pidHasFile(pid: usize, target: []const u8) bool {
    var fd_path_buf: [128]u8 = undefined;
    const fd_dir_path = std.fmt.bufPrint(&fd_path_buf, "/proc/{d}/fd", .{pid}) catch return false;

    var z_buf: [256:0]u8 = undefined;
    if (fd_dir_path.len >= z_buf.len) return false;
    @memcpy(z_buf[0..fd_dir_path.len], fd_dir_path);
    z_buf[fd_dir_path.len] = 0;
    const dir = core.c.opendir(&z_buf);
    if (dir == null) return false;
    defer _ = core.c.closedir(dir);

    while (true) {
        const entry = core.c.readdir(dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (name[0] == '.') continue;
        _ = std.fmt.parseUnsigned(usize, name, 10) catch continue;

        var link_buf: [4096]u8 = undefined;
        var link_path_buf: [256]u8 = undefined;
        const link_path = std.fmt.bufPrint(&link_path_buf, "/proc/{d}/fd/{s}", .{ pid, name }) catch continue;
        const link_z = if (link_path.len < z_buf.len) blk: {
            @memcpy(z_buf[0..link_path.len], link_path);
            z_buf[link_path.len] = 0;
            break :blk z_buf[0..link_path.len :0];
        } else return false;

        const n = core.c.readlink(link_z.ptr, @as([*c]u8, @ptrCast(&link_buf)), link_buf.len);
        if (n < 0) continue;
        const link = link_buf[0..@intCast(n)];

        if (std.mem.eql(u8, link, target)) return true;
    }
    return false;
}

fn pidHasFileInMaps(pid: usize, target: []const u8) bool {
    var path_buf: [128]u8 = undefined;
    const map_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/maps", .{pid}) catch return false;
    var z_buf: [256:0]u8 = undefined;
    if (map_path.len >= z_buf.len) return false;
    @memcpy(z_buf[0..map_path.len], map_path);
    z_buf[map_path.len] = 0;
    const fd = core.c.open(&z_buf, core.c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 65536) catch return false;
    defer alloc.free(data);

    var pos: usize = 0;
    while (pos < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[pos..], '\n') orelse data.len;
        const line = data[pos .. pos + nl];
        pos += nl + 1;
        if (line.len == 0) continue;
        const path_start = std.mem.lastIndexOfScalar(u8, line, ' ') orelse continue;
        const map_file = line[path_start + 1 ..];
        if (map_file.len == 0 or map_file[0] != '/') continue;
        if (std.mem.eql(u8, map_file, target)) return true;
    }
    return false;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: fuser [-k] [-v] [-n SPACE] FILE\n", .{});

    var i: usize = 1;
    var opt_kill = false;
    var opt_verbose = false;
    var opt_namespace: []const u8 = "file";

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) {
            i += 1;
            break;
        }
        if (std.mem.eql(u8, args[i], "-k")) {
            opt_kill = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-v")) {
            opt_verbose = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-n")) {
            i += 1;
            if (i >= args.len) return core.die(1, "fuser: -n requires argument\n", .{});
            opt_namespace = args[i];
            i += 1;
        } else return core.die(1, "fuser: unknown option '{s}'\n", .{args[i]});
    }

    if (i >= args.len) return core.die(1, "fuser: no file specified\n", .{});
    const target_file = args[i];

    if (!std.mem.eql(u8, opt_namespace, "file"))
        return core.die(1, "fuser: only 'file' namespace supported\n", .{});

    var pids: std.ArrayListAligned(usize, null) = .empty;

    const proc_dir = core.c.opendir("/proc");
    if (proc_dir == null) return core.die(1, "fuser: cannot open /proc\n", .{});
    defer _ = core.c.closedir(proc_dir);

    while (true) {
        const entry = core.c.readdir(proc_dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        const pid = std.fmt.parseUnsigned(usize, name, 10) catch continue;

        if (pidHasFile(pid, target_file) or pidHasFileInMaps(pid, target_file)) {
            pids.append(alloc, pid) catch {};
        }
    }

    if (opt_verbose) {
        for (pids.items) |pid| {
            var buf: [64]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{d:>5}  {s}\n", .{ pid, target_file }) catch continue;
            core.writeAll(1, line);
        }
    } else {
        var first = true;
        for (pids.items) |pid| {
            if (!first) core.writeAll(1, " ");
            first = false;
            var buf: [32]u8 = undefined;
            const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch continue;
            core.writeAll(1, pid_str);
        }
        if (pids.items.len > 0) core.writeAll(1, "\n");
    }

    if (opt_kill) {
        for (pids.items) |pid| {
            _ = core.c.kill(@intCast(pid), core.c.SIGKILL);
        }
    }

    return if (pids.items.len == 0) 1 else 0;
}
