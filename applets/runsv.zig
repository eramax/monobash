const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "runsv", .main = main };

const S_DOWN: u8 = 0;
const S_RUN: u8 = 1;
const S_FINISH: u8 = 2;
const C_NOOP: u8 = 0;
const C_TERM: u8 = 1;
const C_PAUSE: u8 = 2;
const W_UP: u8 = 0;
const W_DOWN: u8 = 1;
const W_EXIT: u8 = 2;

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    if (args.len < 2) return core.die(1, "usage: runsv DIR\n", .{});
    const dir = args[1];

    var z_buf: [4096:0]u8 = undefined;
    // Create supervise directory
    var sup_path: [4096]u8 = undefined;
    const sup_dir = std.fmt.bufPrint(&sup_path, "{s}/supervise", .{dir}) catch return 1;
    if (sup_dir.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..sup_dir.len], sup_dir);
    z_buf[sup_dir.len] = 0;
    _ = core.c.mkdir(z_buf[0..sup_dir.len :0].ptr, 0o755);

    // Create control fifo
    var ctrl_path: [4096]u8 = undefined;
    const ctrl = std.fmt.bufPrint(&ctrl_path, "{s}/supervise/control", .{dir}) catch return 1;
    @memcpy(z_buf[0..ctrl.len], ctrl);
    z_buf[ctrl.len] = 0;
    _ = core.c.unlink(z_buf[0..ctrl.len :0].ptr);
    _ = core.c.mkfifo(z_buf[0..ctrl.len :0].ptr, 0o600);

    // Create status file
    var stat_path: [4096]u8 = undefined;
    const stat_file = std.fmt.bufPrint(&stat_path, "{s}/supervise/status", .{dir}) catch return 1;
    @memcpy(z_buf[0..stat_file.len], stat_file);
    z_buf[stat_file.len] = 0;
    const stat_fd = core.c.open(z_buf[0..stat_file.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT, @as(c_uint, 0o644));
    if (stat_fd >= 0) _ = core.c.close(stat_fd);

    // Open control fifo for reading
    @memcpy(z_buf[0..ctrl.len], ctrl);
    z_buf[ctrl.len] = 0;
    const ctrl_fd = core.c.open(z_buf[0..ctrl.len :0].ptr, core.c.O_RDONLY | core.c.O_NONBLOCK);
    if (ctrl_fd < 0) return 1;

    // Determine the run script
    var run_path: [4096]u8 = undefined;
    const run_script = std.fmt.bufPrint(&run_path, "{s}/run", .{dir}) catch return 1;
    @memcpy(z_buf[0..run_script.len], run_script);
    z_buf[run_script.len] = 0;

    // Check if finish script exists
    var fin_path: [4096]u8 = undefined;
    const fin_script = std.fmt.bufPrint(&fin_path, "{s}/finish", .{dir}) catch return 1;

    // Check for log subdirectory
    var log_path: [4096]u8 = undefined;
    _ = std.fmt.bufPrint(&log_path, "{s}/log", .{dir}) catch "";

    var pid: c_int = 0;
    var state: u8 = S_DOWN;
    var want: u8 = W_UP;
    var ctrl_val: u8 = C_NOOP;

    while (want != W_EXIT) {
        // Read control commands
        var ctrl_byte: u8 = undefined;
        const n = core.c.read(ctrl_fd, @as([*]u8, @ptrCast(&ctrl_byte)), 1);
        if (n > 0) {
            switch (ctrl_byte) {
                'u' => { want = W_UP; ctrl_val = C_NOOP; },
                'd' => { want = W_DOWN; ctrl_val = C_TERM; },
                'x' => { want = W_EXIT; ctrl_val = C_TERM; },
                'o' => { want = W_UP; ctrl_val = C_NOOP; },
                't' => ctrl_val = C_TERM,
                'p' => ctrl_val = C_PAUSE,
                else => {},
            }
        }

        if (want == W_EXIT) {
            if (pid > 0) _ = core.c.kill(pid, core.c.SIGTERM);
            break;
        }

        if (state == S_DOWN and want == W_UP) {
            // Start the service
            pid = core.c.fork();
            if (pid < 0) {
                core.eprint("runsv: fork failed\n", .{});
                _ = core.c.sleep(1);
                continue;
            }
            if (pid == 0) {
                // Child: exec the run script
                _ = core.c.setsid();
                var argv = alloc.alloc([*c]u8, 2) catch core.c._exit(111);
                argv[0] = @as([*c]u8, @ptrCast(z_buf[0..run_script.len :0].ptr));
                argv[1] = null;
                _ = core.c.execve(argv[0], argv.ptr, core.environ);
                core.c._exit(111);
            }
            state = S_RUN;
        }

        if (state == S_RUN and pid > 0) {
            var wstatus: c_int = 0;
            const waited = core.c.waitpid(pid, &wstatus, core.c.WNOHANG);
            if (waited == pid) {
                // Process exited
                pid = 0;
                if (core.c.WIFEXITED(wstatus) and core.c.WEXITSTATUS(wstatus) != 0) {
                    // Run finish script if it exists
                    @memcpy(z_buf[0..fin_script.len], fin_script);
                    z_buf[fin_script.len] = 0;
                    if (core.c.access(z_buf[0..fin_script.len :0].ptr, core.c.X_OK) == 0) {
                        state = S_FINISH;
                        const fpid = core.c.fork();
                        if (fpid == 0) {
                            var argv = alloc.alloc([*c]u8, 3) catch core.c._exit(111);
                            argv[0] = @as([*c]u8, @ptrCast(z_buf[0..fin_script.len :0].ptr));
                            var exit_buf: [16]u8 = undefined;
                            const exit_str = std.fmt.bufPrint(&exit_buf, "{d}", .{core.c.WEXITSTATUS(wstatus)}) catch core.c._exit(111);
                            argv[1] = alloc.dupeZ(u8, exit_str) catch core.c._exit(111);
                            argv[2] = null;
                            _ = core.c.execve(argv[0], argv.ptr, core.environ);
                            core.c._exit(111);
                        }
                        if (fpid > 0) {
                            _ = core.c.waitpid(fpid, &wstatus, 0);
                        }
                    }
                }
                state = S_DOWN;
                // Brief pause before restart
                _ = core.c.sleep(1);
            }
        }

        // Send signals based on ctrl_val
        if (ctrl_val != C_NOOP and pid > 0) {
            switch (ctrl_val) {
                C_TERM => _ = core.c.kill(pid, core.c.SIGTERM),
                C_PAUSE => _ = core.c.kill(pid, core.c.SIGSTOP),
                else => {},
            }
            ctrl_val = C_NOOP;
        }

        _ = core.c.sleep(0);
    }

    _ = core.c.close(ctrl_fd);
    _ = core.c.unlink(z_buf[0..ctrl.len :0].ptr);
    return 0;
}
