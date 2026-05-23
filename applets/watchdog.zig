const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "watchdog", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var opt_foreground = false;
    var stimer_ms: u64 = 0;
    var htimer_sec: u64 = 60;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-F")) { opt_foreground = true; i += 1; continue; }
        if (std.mem.eql(u8, args[i], "-t")) {
            i += 1;
            if (i >= args.len) return core.die(1, "watchdog: -t requires N\n", .{});
            stimer_ms = parseMs(args[i]) catch return core.die(1, "watchdog: invalid timeout '{s}'\n", .{args[i]});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-T")) {
            i += 1;
            if (i >= args.len) return core.die(1, "watchdog: -T requires N\n", .{});
            htimer_sec = parseMs(args[i]) catch return core.die(1, "watchdog: invalid timeout '{s}'\n", .{args[i]});
            htimer_sec = htimer_sec / 1000;
            i += 1;
            continue;
        }
        return core.die(1, "watchdog: unknown option '{s}'\n", .{args[i]});
    }

    if (i >= args.len) return core.die(1, "usage: watchdog [-t N[ms]] [-T N[ms]] [-F] DEV\n", .{});

    if (stimer_ms == 0) stimer_ms = htimer_sec * 1000 / 2;

    const device = args[i];

    // Daemonize unless -F
    if (!opt_foreground) {
        const pid = core.c.fork();
        if (pid < 0) return 1;
        if (pid > 0) return 0; // parent exits
        _ = core.c.setsid();
    }

    // Open watchdog device on fd 3
    var z_buf: [4096:0]u8 = undefined;
    if (device.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..device.len], device);
    z_buf[device.len] = 0;

    const wd_fd = core.c.open(z_buf[0..device.len :0].ptr, core.c.O_WRONLY);
    if (wd_fd < 0) return core.die(1, "watchdog: cannot open '{s}'\n", .{device});

    // Set timeout via ioctl
    const WDIOC_SETTIMEOUT: u64 = 0x5706;
    _ = core.c.ioctl(wd_fd, WDIOC_SETTIMEOUT, &htimer_sec);

    // Periodic write
    while (true) {
        _ = core.c.write(wd_fd, "", 1);
        if (stimer_ms >= 1000) {
            _ = core.c.sleep(@intCast(stimer_ms / 1000));
        } else {
            var ts = core.c.struct_timespec{ .tv_sec = 0, .tv_nsec = @intCast(stimer_ms * 1000000) };
            _ = core.c.nanosleep(&ts, null);
        }
    }

    return 0;
}

fn parseMs(s: []const u8) !u64 {
    if (std.mem.endsWith(u8, s, "ms")) {
        return std.fmt.parseUnsigned(u64, s[0 .. s.len - 2], 10);
    }
    const val = try std.fmt.parseUnsigned(u64, s, 10);
    return val * 1000;
}
