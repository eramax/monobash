const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "time", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) {
        core.eprint("usage: time [-v] PROG [ARGS]\n", .{});
        return 1;
    }

    var i: usize = 1;
    var verbose = false;
    if (std.mem.eql(u8, args[i], "-v")) {
        verbose = true;
        i += 1;
    }
    if (i >= args.len) {
        core.eprint("usage: time [-v] PROG [ARGS]\n", .{});
        return 1;
    }

    const prog = args[i];
    i += 1;

    // Build argv
    const alloc = std.heap.page_allocator;
    var argv = alloc.alloc([*c]u8, args.len - i + 2) catch return 1;
    defer alloc.free(argv);
    var argc: usize = 0;
    argv[argc] = alloc.dupeZ(u8, prog) catch return 1;
    argc += 1;
    while (i < args.len) : (i += 1) {
        argv[argc] = alloc.dupeZ(u8, args[i]) catch return 1;
        argc += 1;
    }
    argv[argc] = null;

    var before: core.c.struct_timeval = undefined;
    _ = core.c.gettimeofday(&before, null);

    const pid = core.c.fork();
    if (pid < 0) return core.die(1, "time: fork failed\n", .{});

    if (pid == 0) {
        // Child
        _ = core.c.execvp(prog.ptr, argv.ptr);
        _ = core.c._exit(127);
    }

    // Parent
    var wstatus: c_int = 0;
    var usage: core.c.struct_rusage = undefined;
    _ = core.c.wait4(pid, &wstatus, 0, &usage);

    var after: core.c.struct_timeval = undefined;
    _ = core.c.gettimeofday(&after, null);

    const elapsed_us = (@as(u64, @intCast(after.tv_sec)) * 1000000 + @as(u64, @intCast(after.tv_usec))) -
        (@as(u64, @intCast(before.tv_sec)) * 1000000 + @as(u64, @intCast(before.tv_usec)));
    const elapsed_s = @as(f64, @floatFromInt(elapsed_us)) / 1000000.0;

    const user_us = @as(u64, @intCast(usage.ru_utime.tv_sec)) * 1000000 + @as(u64, @intCast(usage.ru_utime.tv_usec));
    const sys_us = @as(u64, @intCast(usage.ru_stime.tv_sec)) * 1000000 + @as(u64, @intCast(usage.ru_stime.tv_usec));
    const user_s = @as(f64, @floatFromInt(user_us)) / 1000000.0;
    const sys_s = @as(f64, @floatFromInt(sys_us)) / 1000000.0;

    if (verbose) {
        var out: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&out,
            \\Command being timed: "{s}"
            \\User time (seconds): {d:.3}
            \\System time (seconds): {d:.3}
            \\Percent of CPU this job got: {d:.0}%
            \\Elapsed (wall clock) time (h:mm:ss or m:ss): {d:.2}
            \\Major (requiring I/O) page faults: {d}
            \\Minor (reclaiming a frame) page faults: {d}
            \\Voluntary context switches: {d}
            \\Involuntary context switches: {d}
            \\Exit status: {d}
            \\
        , .{
            prog, user_s, sys_s,
            if (elapsed_s > 0) @as(f64, @floatFromInt(user_us + sys_us)) / @as(f64, @floatFromInt(elapsed_us)) * 100 else 0,
            elapsed_s,
            @as(c_long, 0), @as(c_long, 0),
            @as(c_long, 0), @as(c_long, 0),
            wstatus,
        }) catch return 1;
        core.writeAll(1, s);
    } else {
        // Default output: real %e\nuser %u\nsys %T
        var out: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&out, "real {d:.2}\nuser {d:.2}\nsys {d:.2}\n", .{ elapsed_s, user_s, sys_s }) catch return 1;
        core.writeAll(1, s);
    }

    if (core.c.WIFEXITED(wstatus)) return @intCast(core.c.WEXITSTATUS(wstatus));
    return 1;
}
