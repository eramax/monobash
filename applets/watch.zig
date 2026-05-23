const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "watch", .main = main };
pub fn main(args: [][]const u8) u8 {
    var interval: u64 = 2;
    var highlight = false;
    var i: usize = 1;
    var cmd_start: usize = args.len;
    while (i < args.len) {
        const arg = args[i];
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-n")) {
                i += 1;
                if (i >= args.len) return core.die(1, "watch: missing interval\n", .{});
                interval = std.fmt.parseInt(u64, args[i], 10) catch return core.die(1, "watch: invalid interval\n", .{});
            } else if (std.mem.eql(u8, arg, "-d")) {
                highlight = true;
            } else if (std.mem.eql(u8, arg, "--")) {
                i += 1;
                cmd_start = i;
                break;
            } else return core.die(1, "watch: unknown flag '{s}'\n", .{arg});
        } else {
            cmd_start = i;
            break;
        }
        i += 1;
    }
    if (cmd_start >= args.len) return core.die(1, "watch: missing command\n", .{});
    const alloc = std.heap.page_allocator;
    var prev: ?[]u8 = null;
    while (true) {
        var pipe_fds: [2]c_int = undefined;
        if (core.c.pipe(&pipe_fds) < 0) return 1;
        const pid = core.c.fork();
        if (pid < 0) return 1;
        if (pid == 0) {
            _ = core.c.close(pipe_fds[0]);
            _ = core.c.dup2(pipe_fds[1], 1);
            _ = core.c.close(pipe_fds[1]);
            var c_argv = alloc.alloc([*c]u8, args.len - cmd_start + 1) catch std.process.exit(126);
            defer alloc.free(c_argv);
            for (args[cmd_start..], 0..) |arg, j| {
                c_argv[j] = (alloc.dupeZ(u8, arg) catch std.process.exit(126)).ptr;
            }
            c_argv[args.len - cmd_start] = null;
            _ = core.c.execvp(c_argv[0], c_argv.ptr);
            std.process.exit(127);
        }
        _ = core.c.close(pipe_fds[1]);
        const output = core.readAll(alloc, pipe_fds[0], 1024 * 1024) catch { _ = core.c.close(pipe_fds[0]); return 1; };
        _ = core.c.close(pipe_fds[0]);
        var status: c_int = 0;
        _ = core.c.waitpid(pid, @ptrCast(&status), 0);
        core.writeAll(1, "\x1b[H\x1b[2J");
        var hbuf: [512]u8 = undefined;
        const ts = std.fmt.bufPrint(&hbuf, "Every {d}s: ", .{interval}) catch "";
        core.writeAll(1, ts);
        var j: usize = cmd_start;
        while (j < args.len) {
            core.writeAll(1, args[j]);
            if (j + 1 < args.len) core.writeAll(1, " ");
            j += 1;
        }
        core.writeAll(1, "\n\n");
        if (highlight) {
            if (prev) |p| {
                if (!std.mem.eql(u8, p, output)) {
                    core.writeAll(1, "[ differences detected ]\n");
                }
            }
        }
        core.writeAll(1, output);
        if (prev) |p| alloc.free(p);
        prev = output;
        _ = core.c.sleep(@intCast(interval));
    }
    return 0;
}
