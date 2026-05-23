const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ping6", .main = main };

const ICMP6_ECHO: u8 = 128;
const ICMP6_ECHOREPLY: u8 = 129;
const PKT_SZ: usize = 64;

fn icmp_checksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 1 < data.len) {
        sum += @as(u32, data[i]) << 8 | data[i + 1];
        i += 2;
    }
    if (i < data.len) sum += @as(u32, data[i]) << 8;
    while (sum > 0xFFFF) sum = (sum & 0xFFFF) + (sum >> 16);
    return @as(u16, @intCast(~sum & 0xFFFF));
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: ping6 HOST\n", .{});
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
    if (rc != 0 or res == null) return core.die(1, "ping6: unknown host\n", .{});
    defer core.c.freeaddrinfo(res);

    const sock = core.c.socket(core.c.AF_INET6, core.c.SOCK_RAW, core.c.IPPROTO_ICMPV6);
    if (sock < 0) return core.die(1, "ping6: need root\n", .{});

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var addr_str_buf: [64]u8 = undefined;
    var addr_str_sl: []u8 = "";
    const sa = res.?.*.ai_addr;
    if (sa.*.sa_family == core.c.AF_INET6) {
        const sin6: *core.c.struct_sockaddr_in6 = @ptrCast(@alignCast(sa));
        const p = core.c.inet_ntop(core.c.AF_INET6, &sin6.sin6_addr, &addr_str_buf, addr_str_buf.len);
        addr_str_sl = std.mem.sliceTo(@as([*]u8, @constCast(@ptrCast(p))), 0);
    }

    core.writeAll(1, "PING6 ");
    core.writeAll(1, host);
    if (addr_str_sl.len > 0) {
        core.writeAll(1, " (");
        core.writeAll(1, addr_str_sl);
        core.writeAll(1, ")");
    }
    core.writeAll(1, " 64 bytes of data.\n");

    var dst: core.c.struct_sockaddr_in6 = undefined;
    const src_sa = res.?.*.ai_addr;
    if (src_sa.*.sa_family == core.c.AF_INET6) {
        const src_sin6: *core.c.struct_sockaddr_in6 = @ptrCast(@alignCast(src_sa));
        dst = src_sin6.*;
    }

    const pid = @as(u16, @intCast(@as(c_uint, @bitCast(core.c.getpid())) & 0xFFFF));
    var sent: usize = 0;
    var recv: usize = 0;

    for (0..4) |seq| {
        var pkt: [PKT_SZ]u8 = undefined;
        @memset(&pkt, 0);
        pkt[0] = ICMP6_ECHO;
        pkt[1] = 0;
        pkt[4] = @as(u8, @intCast(pid >> 8));
        pkt[5] = @as(u8, @intCast(pid & 0xFF));
        pkt[6] = @as(u8, @intCast(seq >> 8));
        pkt[7] = @as(u8, @intCast(seq & 0xFF));
        for (8..PKT_SZ) |j| pkt[j] = @as(u8, @intCast(j));

        const cksum = icmp_checksum(pkt[0..]);
        pkt[2] = @as(u8, @intCast(cksum >> 8));
        pkt[3] = @as(u8, @intCast(cksum & 0xFF));

        var ts_before: core.c.struct_timespec = undefined;
        _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_before);

        const n = core.c.sendto(sock, &pkt, PKT_SZ, 0,
            .{ .__sockaddr_in6__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));
        sent += 1;
        if (n < 0) {
            core.writeAll(1, "ping6: sendto failed\n");
            continue;
        }

        var buf: [1024]u8 = undefined;
        var from: core.c.struct_sockaddr_in6 = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const rn = core.c.recvfrom(sock, &buf, buf.len, 0,
            .{ .__sockaddr_in6__ = @ptrCast(&from) }, &fromlen);

        if (rn < 0) {
            core.writeAll(1, "ping6: timeout\n");
            continue;
        }

        var ts_after: core.c.struct_timespec = undefined;
        _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_after);
        const rtt_ms = (@as(f64, @floatFromInt(ts_after.tv_sec - ts_before.tv_sec)) * 1000.0 +
            @as(f64, @floatFromInt(ts_after.tv_nsec - ts_before.tv_nsec)) / 1_000_000.0);

        icmp_off: {
            if (rn < 8) break :icmp_off;
            if (buf[0] != ICMP6_ECHOREPLY) break :icmp_off;

            const reply_id = (@as(u16, buf[4]) << 8) | buf[5];
            if (reply_id != pid) break :icmp_off;

            recv += 1;
            const p = core.c.inet_ntop(core.c.AF_INET6, &from.sin6_addr, &addr_str_buf, addr_str_buf.len);
            const src_s = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p)), 0);

            var line: [256]u8 = undefined;
            const line_sl = (std.fmt.bufPrint(&line,
                "64 bytes from {s}: icmp_seq={d} time={d:.1} ms\n",
                .{ src_s, seq, rtt_ms },
            ) catch line[0..0]);
            if (line_sl.len > 0) core.writeAll(1, line_sl);
        }
    }

    var stats: [256]u8 = undefined;
    const loss = if (sent > 0)
        (@as(f64, @floatFromInt(sent - recv)) / @as(f64, @floatFromInt(sent))) * 100
    else 0;
    const s = std.fmt.bufPrint(&stats,
        "\n--- {s} ping6 statistics ---\n{d} transmitted, {d} received, {d:.0}% loss\n",
        .{ host, sent, recv, loss },
    ) catch return 0;
    core.writeAll(1, s);

    return if (recv > 0) 0 else 1;
}
