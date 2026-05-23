const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lsof", .main = main };

fn readLink(path: [:0]const u8, buf: []u8) ?[]const u8 {
    const n = core.c.readlink(path.ptr, buf.ptr, buf.len);
    if (n <= 0) return null;
    return buf[0..@intCast(n)];
}

fn getPidUser(_pid: u32) ?u32 {
    var path_buf: [128]u8 = undefined;
    const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{_pid}) catch return null;
    var z_buf: [256:0]u8 = undefined;
    if (stat_path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..stat_path.len], stat_path);
    z_buf[stat_path.len] = 0;
    const fd = core.c.open(z_buf[0..stat_path.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    var data_buf: [1024]u8 = undefined;
    const n = core.c.read(fd, &data_buf, data_buf.len);
    if (n <= 0) return null;
    return null;
}

pub fn main(args: [][]const u8) u8 {
    var filter_pid: ?u32 = null;
    var filter_user: ?[]const u8 = null;
    var filter_network = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-i")) {
            filter_network = true;
        } else if (std.mem.eql(u8, arg, "-p") and i + 1 < args.len) {
            i += 1;
            filter_pid = std.fmt.parseInt(u32, args[i], 10) catch {
                return core.die(1, "lsof: invalid PID: {s}\n", .{args[i]});
            };
        } else if (std.mem.eql(u8, arg, "-u") and i + 1 < args.len) {
            i += 1;
            filter_user = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "lsof: invalid option '{s}'\n", .{arg});
        }
    }

    core.writeAll(1, "COMMAND     PID   FD   TYPE             DEVICE    SIZE       NODE NAME\n");

    const d = core.c.opendir("/proc") orelse return 1;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);

        const pid = std.fmt.parseInt(u32, name, 10) catch continue;

        if (filter_pid) |fp| {
            if (pid != fp) continue;
        }

        // Build fd directory path
        var fd_path_buf: [128]u8 = undefined;
        const fd_dir_path = std.fmt.bufPrint(&fd_path_buf, "/proc/{d}/fd", .{pid}) catch continue;

        var z_buf: [256:0]u8 = undefined;
        if (fd_dir_path.len >= z_buf.len) continue;
        @memcpy(z_buf[0..fd_dir_path.len], fd_dir_path);
        z_buf[fd_dir_path.len] = 0;

        const fd_dir = core.c.opendir(z_buf[0..fd_dir_path.len :0].ptr) orelse continue;
        defer _ = core.c.closedir(fd_dir);

        // Get process name from /proc/PID/comm
        const comm_path = std.fmt.bufPrint(&fd_path_buf, "/proc/{d}/comm", .{pid}) catch continue;
        @memcpy(z_buf[0..comm_path.len], comm_path);
        z_buf[comm_path.len] = 0;
        const comm_fd = core.c.open(z_buf[0..comm_path.len :0].ptr, core.c.O_RDONLY);
        var comm_name: []const u8 = "";
        if (comm_fd >= 0) {
            var cbuf: [64]u8 = undefined;
            const cn = core.c.read(comm_fd, &cbuf, cbuf.len);
            if (cn > 0) {
                comm_name = std.mem.trim(u8, cbuf[0..@intCast(cn)], " \t\r\n");
            }
            _ = core.c.close(comm_fd);
        }

        while (true) {
            const fd_entry = core.c.readdir(fd_dir) orelse break;
            const fd_dirent: *core.c.struct_dirent = @ptrCast(@alignCast(fd_entry));
            const fd_name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&fd_dirent.d_name)), 0);

            if (std.mem.eql(u8, fd_name, ".") or std.mem.eql(u8, fd_name, "..")) continue;

            // Build fd link path
            var link_buf: [4096]u8 = undefined;
            const fd_link_path = std.fmt.bufPrint(&fd_path_buf, "/proc/{d}/fd/{s}", .{pid, fd_name}) catch continue;
            @memcpy(z_buf[0..fd_link_path.len], fd_link_path);
            z_buf[fd_link_path.len] = 0;

            const target = readLink(z_buf[0..fd_link_path.len :0], &link_buf) orelse continue;

            if (filter_network) {
                if (!std.mem.startsWith(u8, target, "socket:") and !std.mem.startsWith(u8, target, "[") and std.mem.indexOf(u8, target, ":") == null) continue;
            }

            // Determine fd type
            const fd_type = if (std.mem.startsWith(u8, target, "/")) "FILE" else if (std.mem.startsWith(u8, target, "pipe:")) "FIFO" else if (std.mem.startsWith(u8, target, "socket:")) "IPv4" else if (std.mem.startsWith(u8, target, "[") and std.mem.indexOf(u8, target, "]") != null) "a_inode" else "CHR";

            var line: [4096]u8 = undefined;
            const out = std.fmt.bufPrint(&line, "{s:<10} {d:>5} {s:<5} {s:<15} {s}\n", .{ comm_name, pid, fd_name, fd_type, target }) catch continue;
            core.writeAll(1, out);
        }
    }

    return 0;
}
