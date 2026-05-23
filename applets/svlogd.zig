const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "svlogd", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: svlogd [-tt] [-r C] [-R C] [-l LEN] [-b BUF] DIR\n", .{});

    var i: usize = 1;
    var opt_timestamp = false;
    var opt_linelen: usize = 1000;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-tt")) { opt_timestamp = true; i += 1; continue; }
        if (args[i][0] == '-' and args[i].len > 1 and args[i][1] == 't') { opt_timestamp = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-l")) {
            i += 1;
            if (i >= args.len) return core.die(1, "svlogd: -l requires LEN\n", .{});
            opt_linelen = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "svlogd: invalid LEN\n", .{});
            if (opt_linelen > 4096) opt_linelen = 4096;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-b")) {
            i += 1;
            if (i >= args.len) return core.die(1, "svlogd: -b requires BUF\n", .{});
            i += 1;
            continue;
        }
        return core.die(1, "svlogd: unknown option '{s}'\n", .{args[i]});
    }

    if (i >= args.len) return core.die(1, "svlogd: directory required\n", .{});
    const logdir = args[i];

    // Open log directory
    var z_buf: [4096:0]u8 = undefined;
    if (logdir.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..logdir.len], logdir);
    z_buf[logdir.len] = 0;

    // Ensure log directory exists
    _ = core.c.mkdir(z_buf[0..logdir.len :0].ptr, 0o755);

    // Read configuration
    var conf_max_size: u64 = 1000000;
    var conf_num_logs: u64 = 10;

    var conf_path: [4096]u8 = undefined;
    const config_file = std.fmt.bufPrint(&conf_path, "{s}/config", .{logdir}) catch {
        return 0;
    };
    if (config_file.len > 0 and config_file.len < z_buf.len) {
        @memcpy(z_buf[0..config_file.len], config_file);
        z_buf[config_file.len] = 0;
        const cfd = core.c.open(z_buf[0..config_file.len :0].ptr, core.c.O_RDONLY);
        if (cfd >= 0) {
            const config_data = core.readAll(std.heap.page_allocator, cfd, 4096) catch "";
            defer std.heap.page_allocator.free(config_data);
            _ = core.c.close(cfd);
            var lines = std.mem.splitScalar(u8, config_data, '\n');
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len == 0 or trimmed[0] == '#') continue;
                if (trimmed[0] == 's') {
                    conf_max_size = std.fmt.parseUnsigned(u64, trimmed[1..], 10) catch continue;
                } else if (trimmed[0] == 'n') {
                    conf_num_logs = std.fmt.parseUnsigned(u64, trimmed[1..], 10) catch continue;
                }
            }
        }
    }

    // Read stdin and write to current log
    var reader = core.LineReader.init(core.c.STDIN_FILENO);
    while (reader.next()) |line| {
        const trimmed = line;
        if (trimmed.len > opt_linelen) continue;

        // Determine current log file path
        var cur_path: [4096]u8 = undefined;
        const current = std.fmt.bufPrint(&cur_path, "{s}/current", .{logdir}) catch continue;
        @memcpy(z_buf[0..current.len], current);
        z_buf[current.len] = 0;

        // Check size and rotate if needed
        var st: core.c.struct_stat = undefined;
        const stat_rc = core.c.stat(z_buf[0..current.len :0].ptr, &st);
        if (stat_rc == 0 and @as(u64, @intCast(st.st_size)) > conf_max_size) {
            rotate(z_buf[0..current.len :0], logdir, conf_num_logs, @as([*:0]u8, @ptrCast(&z_buf)));
        }

        // Open current log for appending
        const fd = core.c.open(z_buf[0..current.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND, @as(c_uint, 0o644));
        if (fd < 0) continue;
        defer _ = core.c.close(fd);

        const ts = core.c.time(null);
        var line_buf: [4096]u8 = undefined;

        if (opt_timestamp) {
            var tm: core.c.struct_tm = undefined;
            const utc_ptr = core.c.localtime_r(&ts, &tm);
            if (utc_ptr != null) {
                const s = std.fmt.bufPrint(&line_buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2} {s}\n", .{
                    tm.tm_year + 1900,
                    tm.tm_mon + 1,
                    tm.tm_mday,
                    tm.tm_hour,
                    tm.tm_min,
                    tm.tm_sec,
                    trimmed,
                }) catch continue;
                core.writeAll(fd, s);
            } else {
                core.writeAll(fd, trimmed);
                core.writeAll(fd, "\n");
            }
        } else {
            core.writeAll(fd, trimmed);
            core.writeAll(fd, "\n");
        }
    }

    return 0;
}

fn rotate(current: [:0]u8, logdir: []const u8, max_logs: u64, scratch: [*:0]u8) void {
    var ts: c_long = undefined;
    _ = core.c.time(@ptrCast(&ts));

    // Move current to @<timestamp>
    var old_path: [4096]u8 = undefined;
    const old = std.fmt.bufPrint(&old_path, "{s}/@", .{logdir}) catch return;
    if (old.len + 20 >= 4096) return;
    @memcpy(scratch[0..old.len], old);
    const ts_str = std.fmt.bufPrint(scratch[old.len..4096], "{d}", .{ts}) catch return;
    scratch[old.len + ts_str.len] = 0;

    _ = core.c.rename(current.ptr, scratch);

    // Remove old log files if too many
    const d = core.c.opendir(scratch[0..old.len :0].ptr);
    if (d == null) return;
    defer _ = core.c.closedir(d);

    // Count @ timestamp files
    var count: u64 = 0;
    var oldest: [256]u8 = undefined;
    var oldest_name: []const u8 = "";
    var first = true;

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dent.d_name)), 0);
        if (name.len == 0 or name[0] != '@') continue;
        count += 1;
        if (first or std.mem.order(u8, name, oldest_name) == .lt) {
            if (name.len < oldest.len) @memcpy(oldest[0..name.len], name);
            oldest_name = oldest[0..name.len];
            first = false;
        }
    }

    while (count > max_logs) {
        var del_path: [4096]u8 = undefined;
        const dp = std.fmt.bufPrint(&del_path, "{s}/{s}", .{ logdir, oldest_name }) catch break;
        @memcpy(scratch[0..dp.len], dp);
        scratch[dp.len] = 0;
        _ = core.c.unlink(scratch);
        count -= 1;
        // Find next oldest
        oldest_name = "";
        first = true;
        // Re-scan (simplified)
        break;
    }
}
