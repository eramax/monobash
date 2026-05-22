const std = @import("std");

pub const AppletEntry = struct {
    name: []const u8,
    mainFn: *const fn (c_int, [*c][*c]u8) callconv(.c) c_int,
};

// Stub: will be populated from coreutils.h at comptime in Task 11
const applet_table: []const AppletEntry = &.{};

pub fn lookup(name: []const u8) ?AppletEntry {
    inline for (applet_table) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}

pub fn run(io: std.Io, name: []const u8, argv: [][]const u8) u8 {
    const entry = lookup(name) orelse return 127;

    // NOEXEC: fork + call main in child
    const pid = c_fork() catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: fork failed\n", .{name}) catch "fork error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 126;
    };

    if (pid == 0) {
        // Build C-style argv and call coreutils main
        const c_argv = std.heap.page_allocator.alloc([*c]u8, argv.len + 1) catch {
            std.process.exit(126);
        };
        defer std.heap.page_allocator.free(c_argv);
        for (argv, 0..) |arg, i| {
            const arg_z = std.heap.page_allocator.dupeZ(u8, arg) catch {
                std.process.exit(126);
            };
            c_argv[i] = arg_z.ptr;
        }
        c_argv[argv.len] = null;
        const exit_code = entry.mainFn(@intCast(argv.len), c_argv.ptr);
        std.process.exit(@intCast(exit_code));
    }

    // Parent: wait for child
    var wstatus: u32 = 0;
    _ = c_waitpid(pid, &wstatus, 0);
    return @as(u8, @truncate((wstatus >> 8) & 0xFF));
}

extern "c" fn fork() c_int;
extern "c" fn waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int;

fn c_fork() !c_int {
    const pid = fork();
    if (pid < 0) return error.ForkFailed;
    return pid;
}

fn c_waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int {
    return waitpid(pid, wstatus, options);
}
