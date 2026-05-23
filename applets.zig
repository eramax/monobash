const std = @import("std");
const core = @import("applets/core.zig");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/wait.h");
});

// Import all applet modules — add new applets here
const applets = struct {
    const _true = @import("applets/true.zig");
    const _false = @import("applets/false.zig");
};

fn Wrapper(comptime meta: core.AppletMeta) core.AppletEntry {
    const T = struct {
        fn call(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
            const alloc = std.heap.page_allocator;
            const args = alloc.alloc([]const u8, @intCast(argc)) catch return 127;
            defer alloc.free(args);
            for (0..@intCast(argc)) |i| args[i] = std.mem.sliceTo(argv[i], 0);
            return @intCast(meta.main(args));
        }
    };
    return .{ .name = meta.name, .mainFn = T.call };
}

// List all applet metas here — add new applets here too
const all_metas = &[_]core.AppletMeta{
    applets._true.meta,
    applets._false.meta,
};

pub fn lookup(name: []const u8) ?core.AppletEntry {
    inline for (all_metas) |meta| {
        if (std.mem.eql(u8, name, meta.name)) {
            return Wrapper(meta);
        }
    }
    return null;
}

pub fn run(io: std.Io, name: []const u8, argv: [][]const u8) u8 {
    const entry = lookup(name) orelse return 127;

    const pid = c_fork() catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: fork failed\n", .{name}) catch "fork error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 126;
    };

    if (pid == 0) {
        const c_argv = std.heap.page_allocator.alloc([*c]u8, argv.len + 1) catch std.process.exit(126);
        defer std.heap.page_allocator.free(c_argv);
        for (argv, 0..) |arg, i| {
            const arg_z = std.heap.page_allocator.dupeZ(u8, arg) catch std.process.exit(126);
            c_argv[i] = arg_z.ptr;
        }
        c_argv[argv.len] = null;
        std.process.exit(@intCast(entry.mainFn(@intCast(argv.len), c_argv.ptr)));
    }

    var wstatus: u32 = 0;
    _ = c_waitpid(pid, &wstatus, 0);
    if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
        return @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))));
    return 1;
}

extern "c" fn fork() c_int;
extern "c" fn waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int;

fn c_fork() !c_int {
    const pid = fork();
    return if (pid < 0) error.ForkFailed else pid;
}

fn c_waitpid(pid: c_int, wstatus: *u32, options: c_int) c_int {
    return waitpid(pid, wstatus, options);
}
