const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "svc", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: svc [-duox] SERVICE_DIR\n", .{});

    var opt_up = false;
    var opt_down = false;
    var opt_once = false;
    var opt_exit = false;

    const opts = args[1];
    if (opts.len < 2 or opts[0] != '-') return core.die(1, "svc: invalid options\n", .{});

    for (opts[1..]) |ch| {
        switch (ch) {
            'u' => opt_up = true,
            'd' => opt_down = true,
            'o' => opt_once = true,
            'x' => opt_exit = true,
            else => return core.die(1, "svc: unknown option '{c}'\n", .{ch}),
        }
    }

    var exit_code: u8 = 0;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const svc_dir = args[i];

        // Build path to the supervise/control fifo
        var ctrl_path: [4096]u8 = undefined;
        const ctrl = std.fmt.bufPrint(&ctrl_path, "{s}/supervise/control", .{svc_dir}) catch {
            core.eprint("svc: path too long\n", .{});
            exit_code = 1;
            continue;
        };

        var z_buf: [4096:0]u8 = undefined;
        if (ctrl.len >= z_buf.len) {
            core.eprint("svc: path too long\n", .{});
            exit_code = 1;
            continue;
        }
        @memcpy(z_buf[0..ctrl.len], ctrl);
        z_buf[ctrl.len] = 0;

        const fd = core.c.open(z_buf[0..ctrl.len :0].ptr, core.c.O_WRONLY | core.c.O_NONBLOCK);
        if (fd < 0) {
            core.eprint("svc: cannot open control pipe for '{s}'\n", .{svc_dir});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        if (opt_up) {
            _ = core.c.write(fd, "u", 1);
            _ = core.c.write(fd, "u", 1); // double 'u' to confirm
        }
        if (opt_down) {
            _ = core.c.write(fd, "d", 1);
        }
        if (opt_once) {
            _ = core.c.write(fd, "o", 1);
        }
        if (opt_exit) {
            _ = core.c.write(fd, "x", 1);
        }
    }

    return exit_code;
}
