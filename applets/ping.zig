const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ping", .main = main };

const ICMP_ECHO: u8 = 8;
const ICMP_ECHOREPLY: u8 = 0;
const PKT_SZ: usize = 64;

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

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
    if (args.len < 2) return core.die(1, "usage: ping HOST\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "ping: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_RAW, core.c.IPPROTO_ICMP);
    if (sock < 0) return core.die(1, "ping: need root (requires CAP_NET_RAW)\n", .{});
    defer _ = core.c.close(sock);

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var dst: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    dst.sin_family = core.c.AF_INET;
    const addr_ptr = he.*.h_addr_list[0] orelse return 1;
    dst.sin_addr.s_addr = netU32(addr_ptr);

    const addr_str = core.c.inet_ntoa(dst.sin_addr);
    core.writeAll(1, "PING ");
    core.writeAll(1, host);
    core.writeAll(1, " (");
    core.writeAll(1, std.mem.sliceTo(addr_str, 0));
    core.writeAll(1, ") 64 bytes of data.\n");

    const pid = @as(u16, @intCast(@as(c_uint, @bitCast(core.c.getpid())) & 0xFFFF));
    var sent: usize = 0;
    var recv: usize = 0;
    var total_rtt: f64 = 0;
    var min_rtt: f64 = 1e9;
    var max_rtt: f64 = 0;

    for (0..4) |seq| {
        var pkt: [PKT_SZ]u8 = undefined;
        @memset(&pkt, 0);
        pkt[0] = ICMP_ECHO;
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
        const before_ns = @as(f64, @floatFromInt(ts_before.tv_sec)) * 1e9 +
            @as(f64, @floatFromInt(ts_before.tv_nsec));

        const n = core.c.sendto(sock, &pkt, PKT_SZ, 0,
            .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));
        sent += 1;
        if (n < 0) {
            core.writeAll(1, "ping: sendto failed\n");
            continue;
        }

        var buf: [1024]u8 = undefined;
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const rn = core.c.recvfrom(sock, &buf, buf.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);

        if (rn < 0) {
            core.writeAll(1, "ping: timeout\n");
            continue;
        }

        var ts_after: core.c.struct_timespec = undefined;
        _ = core.c.clock_gettime(core.c.CLOCK_MONOTONIC, &ts_after);
        const after_ns = @as(f64, @floatFromInt(ts_after.tv_sec)) * 1e9 +
            @as(f64, @floatFromInt(ts_after.tv_nsec));

        const rtt_ms = (after_ns - before_ns) / 1_000_000.0;

        const ihl = (buf[0] & 0x0F) * 4;
        const icmp_off = @as(usize, ihl);
        if (rn < icmp_off + 8) continue;
        if (buf[icmp_off] != ICMP_ECHOREPLY) continue;

        const reply_id = (@as(u16, buf[icmp_off + 4]) << 8) | buf[icmp_off + 5];
        if (reply_id != pid) continue;

        recv += 1;
        total_rtt += rtt_ms;
        if (rtt_ms < min_rtt) min_rtt = rtt_ms;
        if (rtt_ms > max_rtt) max_rtt = rtt_ms;

        var src_in: core.c.struct_in_addr = undefined;
        src_in.s_addr = netU32(buf[12..16].ptr);
        const src_s = std.mem.sliceTo(core.c.inet_ntoa(src_in), 0);

        var line: [128]u8 = undefined;
        const line_sl = (std.fmt.bufPrint(&line,
            "64 bytes from {s}: icmp_seq={d} ttl={d} time={d:.1} ms\n",
            .{ src_s, seq, buf[8], rtt_ms },
        ) catch line[0..0]);
        if (line_sl.len > 0) core.writeAll(1, line_sl);
    }

    var stats: [256]u8 = undefined;
    const loss = if (sent > 0)
        (@as(f64, @floatFromInt(sent - recv)) / @as(f64, @floatFromInt(sent))) * 100
    else 0;
    const avg = if (recv > 0) total_rtt / @as(f64, @floatFromInt(recv)) else 0;
    const s = std.fmt.bufPrint(&stats,
        "\n--- {s} ping statistics ---\n{d} transmitted, {d} received, {d:.0}% loss\n",
        .{ host, sent, recv, loss },
    ) catch return 0;
    core.writeAll(1, s);

    if (recv > 0) {
        var rtt_buf: [128]u8 = undefined;
        const r = std.fmt.bufPrint(&rtt_buf,
            "rtt min/avg/max = {d:.3}/{d:.3}/{d:.3} ms\n",
            .{ min_rtt, avg, max_rtt },
        ) catch return 0;
        core.writeAll(1, r);
    }

    return if (recv > 0) 0 else 1;
}
