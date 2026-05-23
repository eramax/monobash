const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "traceroute6", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: traceroute6 HOST\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    var hints: core.c.struct_addrinfo = std.mem.zeroes(core.c.struct_addrinfo);
    hints.ai_family = core.c.AF_INET6;
    hints.ai_socktype = core.c.SOCK_RAW;
    hints.ai_protocol = core.c.IPPROTO_ICMPV6;

    var res: ?*core.c.struct_addrinfo = null;
    const rc = core.c.getaddrinfo(host_z.ptr, null, &hints, &res);
    if (rc != 0 or res == null) return core.die(1, "traceroute6: unknown host\n", .{});
    defer core.c.freeaddrinfo(res);

    const recv_sock = core.c.socket(core.c.AF_INET6, core.c.SOCK_RAW, core.c.IPPROTO_ICMPV6);
    if (recv_sock < 0) return core.die(1, "traceroute6: need root\n", .{});

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 3;
    _ = core.c.setsockopt(recv_sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var addr_buf: [64]u8 = undefined;
    var addr_str: []u8 = "";
    const sa = res.?.*.ai_addr;
    if (sa.*.sa_family == core.c.AF_INET6) {
        const sin6: *core.c.struct_sockaddr_in6 = @ptrCast(@constCast(@alignCast(sa)));
        const p = core.c.inet_ntop(core.c.AF_INET6, &sin6.sin6_addr, &addr_buf, addr_buf.len);
        addr_str = std.mem.sliceTo(@as([*:0]u8, @constCast(@ptrCast(p))), 0);
    }

    var msg: [256]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "traceroute6 to {s} ({s}), 30 hops max\n", .{ host, addr_str }) catch "traceroute6\n";
    core.writeAll(1, m);

    var dst: core.c.struct_sockaddr_in6 = undefined;
    const src_sa = res.?.*.ai_addr;
    if (src_sa.*.sa_family == core.c.AF_INET6) {
        const src_sin6: *core.c.struct_sockaddr_in6 = @ptrCast(@alignCast(src_sa));
        dst = src_sin6.*;
    }

    const max_ttl: u8 = 30;
    for (1..max_ttl + 1) |ttl| {
        const send_sock = core.c.socket(core.c.AF_INET6, core.c.SOCK_DGRAM, 0);
        if (send_sock < 0) return 1;
        defer _ = core.c.close(send_sock);

        const ttl_c: c_int = @intCast(ttl);
        _ = core.c.setsockopt(send_sock, core.c.IPPROTO_IPV6, core.c.IPV6_UNICAST_HOPS, &ttl_c, @sizeOf(c_int));

        var out: [128]u8 = undefined;
        const o = std.fmt.bufPrint(&out, "{d:>2} ", .{ttl}) catch break;
        core.writeAll(1, o);

        var responded = false;

        for (0..3) |q| {
            _ = q;
            _ = @as(u16, @intCast(33434 + (ttl - 1) * 3));

            var ts_before: core.c.struct_timespec = undefined;
            _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_before);

            _ = core.c.sendto(send_sock, "!", 1, 0,
                .{ .__sockaddr_in6__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

            var buf: [512]u8 = undefined;
            var from: core.c.struct_sockaddr_in6 = undefined;
            var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
            const rn = core.c.recvfrom(recv_sock, &buf, buf.len, 0,
                .{ .__sockaddr_in6__ = @ptrCast(&from) }, &fromlen);

            if (rn >= 0) {
                var ts_after: core.c.struct_timespec = undefined;
                _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_after);
                const rtt_ms = (@as(f64, @floatFromInt(ts_after.tv_sec - ts_before.tv_sec)) * 1000.0 +
                    @as(f64, @floatFromInt(ts_after.tv_nsec - ts_before.tv_nsec)) / 1_000_000.0);

                responded = true;
                const p = core.c.inet_ntop(core.c.AF_INET6, &from.sin6_addr, &addr_buf, addr_buf.len);
                const from_s = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p)), 0);

                var hop: [128]u8 = undefined;
                const h = std.fmt.bufPrint(&hop, "{s} {d:.1}ms ", .{ from_s, rtt_ms }) catch continue;
                core.writeAll(1, h);
            } else {
                core.writeAll(1, "* ");
            }
        }

        core.writeAll(1, "\n");
        if (responded) break;
    }

    return 0;
}
