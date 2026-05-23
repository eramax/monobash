const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "w", .main = main };

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    // Read /var/run/utmp
    const fd = core.c.open("/var/run/utmp", core.c.O_RDONLY);
    if (fd < 0) {
        core.writeAll(1, "w: cannot open /var/run/utmp\n");
        return 1;
    }
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 131072) catch return 1;
    defer alloc.free(data);

    // Read /proc/loadavg
    const lfd = core.c.open("/proc/loadavg", core.c.O_RDONLY);
    var load_data: []u8 = "";
    if (lfd >= 0) {
        load_data = core.readAll(alloc, lfd, 128) catch "";
        _ = core.c.close(lfd);
    }
    defer if (load_data.len > 0) alloc.free(load_data);

    var header: [256]u8 = undefined;
    if (load_data.len > 0) {
        const load_trimmed = std.mem.trim(u8, load_data, " \t\r\n");
        const hdr = std.fmt.bufPrint(&header, "  {s}\nUSER     TTY      FROM             LOGIN@   IDLE   WHAT\n", .{load_trimmed}) catch "";
        core.writeAll(1, hdr);
    } else {
        core.writeAll(1, "USER     TTY      FROM             LOGIN@   IDLE   WHAT\n");
    }

    const utmpx_size = @sizeOf(core.c.struct_utmpx);
    var pos: usize = 0;
    while (pos + utmpx_size <= data.len) : (pos += utmpx_size) {
        const ut = @as(*const core.c.struct_utmpx, @ptrCast(@alignCast(data[pos..][0..utmpx_size])));
        if (ut.ut_type != 7) continue;
        _ = &ut;

        const user = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&ut.ut_user)), 0);
        const tty = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&ut.ut_line)), 0);
        const host = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&ut.ut_host)), 0);

        var line: [256]u8 = undefined;
        // Determine login time
        const login_secs = ut.ut_tv.tv_sec;
        // Get current time for idle calculation
        var now: core.c.struct_timeval = undefined;
        _ = core.c.gettimeofday(&now, null);
        const idle_min = if (now.tv_sec > login_secs) @divTrunc(now.tv_sec - login_secs, @as(c_long, 60)) else @as(u64, 0);

        var idle_str: [8]u8 = undefined;
        const idle_fmt = if (idle_min < 60)
            std.fmt.bufPrint(&idle_str, "{d}m", .{idle_min}) catch "?"
        else
            std.fmt.bufPrint(&idle_str, "{d}h", .{@divTrunc(idle_min, @as(c_long, 60))}) catch "?";

        var time_buf: [16]u8 = undefined;
        const login_time = std.fmt.bufPrint(&time_buf, "{d}:{d:0>2}", .{
            (login_secs % 86400) / 3600,
            (login_secs % 3600) / 60,
        }) catch continue;

        // Get the process name from /proc for this tty
        const tty_nr = ut.ut_pid;
        var cmd: []const u8 = "-";
        var cmd_buf: [128]u8 = undefined;
        if (tty_nr > 0) {
            const comm_path = std.fmt.bufPrint(&cmd_buf, "/proc/{}/comm", .{@as(c_int, tty_nr)}) catch {
                continue;
            };
            var z_buf: [256:0]u8 = undefined;
            if (comm_path.len < z_buf.len) {
                @memcpy(z_buf[0..comm_path.len], comm_path);
                z_buf[comm_path.len] = 0;
                const cfd = core.c.open(z_buf[0..comm_path.len :0].ptr, core.c.O_RDONLY);
                if (cfd >= 0) {
                    const cdata = core.readAll(alloc, cfd, 64) catch continue;
                    if (cdata.len > 0) {
                        cmd = std.mem.trim(u8, cdata, " \t\r\n");
                    }
                    _ = core.c.close(cfd);
                }
            }
        }

        const s = std.fmt.bufPrint(&line, "{s:<8} {s:<7} {s:<16} {s}  {s:<6} {s}\n", .{ user, tty, host, login_time, idle_fmt, cmd }) catch continue;
        core.writeAll(1, s);
    }

    return 0;
}
