const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "rdate", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: rdate HOST\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "rdate: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    var addr_bytes: [4]u8 = undefined;
    @memcpy(&addr_bytes, ap[0..4]);
    addr.sin_addr.s_addr = @as(u32, @bitCast(addr_bytes));
    addr.sin_port = core.c.htons(37);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "rdate: connection failed\n", .{});

    var buf: [4]u8 = undefined;
    const n = core.c.read(sock, &buf, 4);
    if (n < 4) return core.die(1, "rdate: short read\n", .{});

    const time_raw = (@as(u32, buf[0]) << 24) | (@as(u32, buf[1]) << 16) | (@as(u32, buf[2]) << 8) | buf[3];
    const unix_time = time_raw - 2208988800;

    var tv: core.c.struct_timeval = .{ .tv_sec = @as(c_long, @intCast(unix_time)), .tv_usec = 0 };
    if (core.c.settimeofday(&tv, null) < 0)
        return core.die(1, "rdate: settimeofday failed (need root)\n", .{});

    var out: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&out, "rdate: time set to {d}\n", .{unix_time}) catch "rdate: done\n";
    core.writeAll(1, s);
    return 0;
}
