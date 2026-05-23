const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "script", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    var file_arg: ?[]const u8 = null;
    var append = false;
    var quiet = false;
    var timing_file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-a")) {
            append = true;
        } else if (std.mem.eql(u8, arg, "-q")) {
            quiet = true;
        } else if (std.mem.eql(u8, arg, "-t") and i + 1 < args.len) {
            i += 1;
            timing_file = args[i];
        } else if (arg.len > 0 and arg[0] != '-') {
            file_arg = arg;
        } else {
            return core.die(1, "usage: script [-a] [-q] [-t file] [file]\n", .{});
        }
    }

    const file_name = file_arg orelse "typescript";

    // Create pipes: pipe_out for stdout, pipe_err for stderr
    var out_pipe: [2]c_int = undefined;
    var err_pipe: [2]c_int = undefined;
    if (core.c.pipe(&out_pipe) < 0) return 1;
    if (core.c.pipe(&err_pipe) < 0) return 1;

    const pid = core.c.fork();
    if (pid < 0) return 1;

    if (pid == 0) {
        // Child: redirect stdout/stderr to pipes, exec shell
        _ = core.c.close(out_pipe[0]);
        _ = core.c.close(err_pipe[0]);
        _ = core.c.dup2(out_pipe[1], 1);
        _ = core.c.dup2(err_pipe[1], 2);
        _ = core.c.close(out_pipe[1]);
        _ = core.c.close(err_pipe[1]);
        // Try to exec the user's shell
        const shell = core.c.getenv("SHELL") orelse @as([*:0]u8, @ptrFromInt(@intFromPtr("/bin/sh")));
        const c_argv = alloc.alloc([*c]u8, 2) catch core.c._exit(1);
        c_argv[0] = @as([*c]u8, @ptrFromInt(@intFromPtr(shell)));
        c_argv[1] = null;
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }

    // Parent: close write ends
    _ = core.c.close(out_pipe[1]);
    _ = core.c.close(err_pipe[1]);

    // Open output file
    var zpath: [4096:0]u8 = undefined;
    if (file_name.len >= zpath.len) return 1;
    @memcpy(zpath[0..file_name.len], file_name);
    zpath[file_name.len] = 0;
    const flags = core.c.O_WRONLY | core.c.O_CREAT | (if (append) core.c.O_APPEND else core.c.O_TRUNC);
    const out_fd = core.c.open(zpath[0..file_name.len :0].ptr, flags, @as(c_uint, 0o644));
    if (out_fd < 0) return core.die(1, "script: cannot open {s}\n", .{file_name});

    if (!quiet) {
        core.writeAll(1, "Script started, output file: ");
        core.writeAll(1, file_name);
        core.writeAll(1, "\n");
    }

    var fds = [_]c_int{ out_pipe[0], err_pipe[0] };

    loop: while (true) {
        for (&fds) |fd| {
            if (fd < 0) continue;
            const data = core.readAll(std.heap.page_allocator, fd, 4096) catch continue;
            defer std.heap.page_allocator.free(data);
            if (data.len > 0) {
                core.writeAll(out_fd, data);
                core.writeAll(1, data);
            }
        }

        // Check if child is done
        var wstatus: c_int = 0;
        const wpid = core.c.waitpid(pid, &wstatus, core.c.WNOHANG);
        if (wpid == pid) break :loop;
        if (wpid < 0) break :loop;

        // Sleep a bit to avoid busy-waiting
        _ = core.c.usleep(10000);
    }

    _ = core.c.close(out_fd);
    _ = core.c.close(out_pipe[0]);
    _ = core.c.close(err_pipe[0]);

    if (!quiet) {
        core.writeAll(1, "Script done, output file: ");
        core.writeAll(1, file_name);
        core.writeAll(1, "\n");
    }

    return 0;
}
