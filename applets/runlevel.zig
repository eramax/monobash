const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "runlevel", .main = main };

const utmpx = extern struct {
    ut_type: c_short,
    ut_pid: c_int,
    ut_line: [32]u8,
    ut_id: [4]u8,
    ut_user: [32]u8,
    ut_host: [256]u8,
    ut_exit: [2]c_int,
    ut_session: c_int,
    ut_tv: [2]c_int,
    ut_addr_v6: [4]c_int,
    __unused: [20]u8,
};

pub fn main(args: [][]const u8) u8 {
    const utmp_file = if (args.len > 1) args[1] else "/var/run/utmp";

    var z_buf: [512:0]u8 = undefined;
    if (utmp_file.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..utmp_file.len], utmp_file);
    z_buf[utmp_file.len] = 0;

    const fd = core.c.open(z_buf[0..utmp_file.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) {
        core.writeAll(1, "unknown\n");
        return 1;
    }
    defer _ = core.c.close(fd);

    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, fd, 65536) catch {
        core.writeAll(1, "unknown\n");
        return 1;
    };
    defer alloc.free(data);

    const utmpx_size = @sizeOf(utmpx);
    var pos: usize = 0;
    while (pos + utmpx_size <= data.len) : (pos += utmpx_size) {
        const ut = @as(*const utmpx, @ptrCast(@alignCast(data[pos..][0..utmpx_size])));
        if (ut.ut_type == 1) {
            const prev = if (@divTrunc(ut.ut_pid, 256) == 0) 'N' else @as(u8, @intCast(@divTrunc(ut.ut_pid, 256)));
            const curr = @as(u8, @intCast(@rem(ut.ut_pid, 256)));
            var out: [8]u8 = undefined;
            const s = std.fmt.bufPrint(&out, "{c} {c}\n", .{ prev, curr }) catch return 1;
            core.writeAll(1, s);
            return 0;
        }
    }

    core.writeAll(1, "unknown\n");
    return 1;
}
