const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "runsvdir", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    if (args.len < 2) return core.die(1, "usage: runsvdir [-P] DIR\n", .{});

    var i: usize = 1;
    var opt_session = false;

    if (std.mem.eql(u8, args[i], "-P")) {
        opt_session = true;
        i += 1;
    }

    if (i >= args.len) return core.die(1, "runsvdir: directory required\n", .{});
    const svdir = args[i];

    // Become session leader
    if (opt_session) _ = core.c.setsid();

    var children: std.ArrayListAligned(c_int, null) = .empty;
    defer children.deinit(alloc);

    while (true) {
        // Scan the service directory
        var z_buf: [4096:0]u8 = undefined;
        if (svdir.len >= z_buf.len) return 1;
        @memcpy(z_buf[0..svdir.len], svdir);
        z_buf[svdir.len] = 0;

        const d = core.c.opendir(z_buf[0..svdir.len :0].ptr) orelse {
            core.eprint("runsvdir: cannot open '{s}'\n", .{svdir});
            return 1;
        };
        defer _ = core.c.closedir(d);

        // Track which children are still alive
        var alive: std.ArrayListAligned(c_int, null) = .empty;
        defer alive.deinit(alloc);

        while (true) {
            const entry = core.c.readdir(d) orelse break;
            const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
            const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
            if (name[0] == '.') continue;

            // Check if this is a service directory (has a "run" file)
            var run_path: [4096]u8 = undefined;
            const run = std.fmt.bufPrint(&run_path, "{s}/{s}/run", .{ svdir, name }) catch continue;
            if (run.len >= z_buf.len) continue;
            @memcpy(z_buf[0..run.len], run);
            z_buf[run.len] = 0;

            if (core.c.access(z_buf[0..run.len :0].ptr, core.c.X_OK) != 0) continue;

            // Check if we already have a child for this service
            var already_running = false;
            for (children.items) |cpid| {
                if (cpid > 0) {
                    var wstatus: c_int = 0;
                    const waited = core.c.waitpid(cpid, &wstatus, core.c.WNOHANG);
                    if (waited == cpid) {
                        // Child died, will be restarted
                    } else if (waited == 0) {
                        alive.append(alloc, cpid) catch {};
                        already_running = true;
                    }
                }
            }

            if (!already_running) {
                // Fork a runsv for this service
                const pid = core.c.fork();
                if (pid < 0) {
                    core.eprint("runsvdir: fork failed\n", .{});
                    continue;
                }
                if (pid == 0) {
                    // Child: exec runsv on this service dir
                    var svc_dir: [4096]u8 = undefined;
                    const sd = std.fmt.bufPrint(&svc_dir, "{s}/{s}", .{ svdir, name }) catch core.c._exit(111);
                    @memcpy(z_buf[0..sd.len], sd);
                    z_buf[sd.len] = 0;

                    // Find runsv in PATH
                    var argv = alloc.alloc([*c]u8, 3) catch core.c._exit(111);
                    // Try to find runsv using argv[0] resolution
                    argv[0] = @as([*c]u8, @ptrCast(@constCast("runsv")));
                    argv[1] = @as([*c]u8, @ptrCast(z_buf[0..sd.len :0].ptr));
                    argv[2] = null;
                    _ = core.c.execvp("runsv", argv.ptr);
                    core.c._exit(111);
                }
                if (pid > 0) {
                    alive.append(alloc, pid) catch {};
                }
            }
        }

        children = alive;

        // Sleep before re-scanning
        _ = core.c.sleep(5);
    }

    return 0;
}
