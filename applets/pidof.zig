const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "pidof", .main = main };

const alloc = std.heap.page_allocator;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: pidof [-s] [-x] PROGRAM\n", .{});

    var i: usize = 1;
    var opt_single = false;
    var opt_shells = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) {
            i += 1;
            break;
        }
        for (args[i][1..]) |c| {
            switch (c) {
                's' => opt_single = true,
                'x' => opt_shells = true,
                else => return core.die(1, "pidof: unknown option -{c}\n", .{c}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "pidof: no program specified\n", .{});
    const program = args[i];

    const proc_dir = core.c.opendir("/proc");
    if (proc_dir == null) return 1;
    defer _ = core.c.closedir(proc_dir);

    var pids: std.ArrayListAligned(usize, null) = .empty;

    while (true) {
        const entry = core.c.readdir(proc_dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        const pid = std.fmt.parseUnsigned(usize, name, 10) catch continue;

        var comm_buf: [256]u8 = undefined;
        var path_buf: [128]u8 = undefined;
        const comm_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid}) catch continue;
        var z_buf: [256:0]u8 = undefined;
        if (comm_path.len >= z_buf.len) continue;
        @memcpy(z_buf[0..comm_path.len], comm_path);
        z_buf[comm_path.len] = 0;

        const comm_fd = core.c.open(&z_buf, core.c.O_RDONLY);
        if (comm_fd < 0) continue;
        defer _ = core.c.close(comm_fd);

        const n = core.c.read(comm_fd, @as([*c]u8, @ptrCast(&comm_buf)), comm_buf.len);
        if (n <= 0) continue;
        const comm = std.mem.trimEnd(u8, comm_buf[0..@intCast(n)], "\n");

        if (std.mem.eql(u8, comm, program)) {
            pids.append(alloc, pid) catch {};
            if (opt_single) break;
            continue;
        }

        if (opt_shells) {
            var exe_link: [256]u8 = undefined;
            const exe_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/exe", .{pid}) catch continue;
            @memcpy(z_buf[0..exe_path.len], exe_path);
            z_buf[exe_path.len] = 0;
            const m = core.c.readlink(&z_buf, @as([*c]u8, @ptrCast(&exe_link)), exe_link.len);
            if (m > 0) {
                const exe_name = std.fs.path.basename(exe_link[0..@intCast(m)]);
                if (std.mem.eql(u8, exe_name, program)) {
                    pids.append(alloc, pid) catch {};
                    if (opt_single) break;
                }
            }
        }
    }

    var first = true;
    for (pids.items) |p| {
        if (!first) core.writeAll(1, " ");
        first = false;
        var buf: [32]u8 = undefined;
        const pid_str = std.fmt.bufPrint(&buf, "{d}", .{p}) catch continue;
        core.writeAll(1, pid_str);
    }
    if (pids.items.len > 0) core.writeAll(1, "\n");

    return if (pids.items.len > 0) 0 else 1;
}
