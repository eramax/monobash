const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "traceroute", .main = main };

const ICMP_TIME_EXCEEDED: u8 = 11;
const ICMP_UNREACH: u8 = 3;

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: traceroute HOST\n", .{});
    const alloc = std.heap.page_allocator;
    var host: []const u8 = "";
    var numeric = false;
    var max_ttl: u8 = 30;
    var nqueries: u8 = 3;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-n")) {
            numeric = true;
        } else if (std.mem.eql(u8, args[i], "-m") and i + 1 < args.len) {
            i += 1;
            max_ttl = std.fmt.parseInt(u8, args[i], 10) catch return core.die(1, "traceroute: bad -m\n", .{});
        } else if (std.mem.eql(u8, args[i], "-q") and i + 1 < args.len) {
            i += 1;
            nqueries = std.fmt.parseInt(u8, args[i], 10) catch return core.die(1, "traceroute: bad -q\n", .{});
        } else if (host.len == 0) {
            host = args[i];
        } else return core.die(1, "usage: traceroute [-n] [-m TTL] [-q N] HOST\n", .{});
    }
    if (host.len == 0) return core.die(1, "usage: traceroute HOST\n", .{});

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "traceroute: unknown host\n", .{});

    var dst_bytes: [4]u8 = undefined;
    const ap = he.*.h_addr_list[0] orelse return 1;
    @memcpy(&dst_bytes, ap[0..4]);
    const dst_addr: u32 = @as(u32, @bitCast(dst_bytes));

    const host_addr_str = std.mem.sliceTo(core.c.inet_ntoa(@as(core.c.struct_in_addr, .{ .s_addr = dst_addr })), 0);

    var msg: [256]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "traceroute to {s} ({s}), {d} hops max\n", .{ host, host_addr_str, max_ttl }) catch "traceroute\n";
    core.writeAll(1, m);

    const recv_sock = core.c.socket(core.c.AF_INET, core.c.SOCK_RAW, core.c.IPPROTO_ICMP);
    if (recv_sock < 0) return core.die(1, "traceroute: need root (CAP_NET_RAW)\n", .{});
    defer _ = core.c.close(recv_sock);

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 3;
    _ = core.c.setsockopt(recv_sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var dst: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    dst.sin_family = core.c.AF_INET;
    dst.sin_addr.s_addr = dst_addr;

    for (1..max_ttl + 1) |ttl| {
        const send_sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
        if (send_sock < 0) return 1;
        defer _ = core.c.close(send_sock);

        const ttl_c: c_int = @intCast(ttl);
        _ = core.c.setsockopt(send_sock, core.c.IPPROTO_IP, core.c.IP_TTL, &ttl_c, @sizeOf(c_int));

        var out: [128]u8 = undefined;
        const o = std.fmt.bufPrint(&out, "{d:>2} ", .{ttl}) catch break;
        core.writeAll(1, o);

        var responded = false;
        var ip_from: u32 = 0;
        var rtt_sum: f64 = 0;
        var have_rtt = false;

        for (0..nqueries) |q| {
            const port: u16 = @intCast(33434 + (ttl - 1) * nqueries + q);
            dst.sin_port = core.c.htons(port);

            var ts_before: core.c.struct_timespec = undefined;
            _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_before);

            _ = core.c.sendto(send_sock, "!", 1, 0,
                .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

            var buf: [512]u8 = undefined;
            var from: core.c.struct_sockaddr_in = undefined;
            var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
            const rn = core.c.recvfrom(recv_sock, &buf, buf.len, 0,
                .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);

            if (rn >= 0) {
                var ts_after: core.c.struct_timespec = undefined;
                _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_after);
                const rtt_ms = (@as(f64, @floatFromInt(ts_after.tv_sec - ts_before.tv_sec)) * 1000.0 +
                    @as(f64, @floatFromInt(ts_after.tv_nsec - ts_before.tv_nsec)) / 1_000_000.0);

                const ip_hdr_len = @as(usize, (@as(u32, buf[0]) & 0x0F) * 4);
                const icmp_type = buf[ip_hdr_len];

                if (icmp_type == ICMP_TIME_EXCEEDED or icmp_type == ICMP_UNREACH) {
                    ip_from = netU32(buf[12..16].ptr);
                    responded = true;
                    rtt_sum += rtt_ms;
                    have_rtt = true;
                }

                var rt: [32]u8 = undefined;
                const r = std.fmt.bufPrint(&rt, "{d:.1} ms ", .{rtt_ms}) catch continue;
                core.writeAll(1, r);
            } else {
                core.writeAll(1, "* ");
            }
        }

        if (responded) {
            const from_str = std.mem.sliceTo(core.c.inet_ntoa(@as(core.c.struct_in_addr, .{ .s_addr = ip_from })), 0);
            var hop: [64]u8 = undefined;
            const h = std.fmt.bufPrint(&hop, "{s}", .{from_str}) catch break;
            core.writeAll(1, h);
        }
        core.writeAll(1, "\n");

        if (responded and ip_from == dst_addr) break;
    }

    return 0;
}
