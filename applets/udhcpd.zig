const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "udhcpd", .main = main };

const DHCP_DISCOVER: u8 = 1;
const DHCP_OFFER: u8 = 2;
const DHCP_REQUEST: u8 = 3;
const DHCP_ACK: u8 = 5;
const DHCP_NAK: u8 = 6;
const DHCP_SERVER_PORT: u16 = 67;
const DHCP_CLIENT_PORT: u16 = 68;

const DhcpPacket = extern struct {
    op: u8,
    htype: u8,
    hlen: u8,
    hops: u8,
    xid: u32,
    secs: u16,
    flags: u16,
    ciaddr: u32,
    yiaddr: u32,
    siaddr: u32,
    giaddr: u32,
    chaddr: [16]u8,
    sname: [64]u8,
    file: [128]u8,
    magic: u32,
    options: [256]u8,
};

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, core.c.IPPROTO_UDP);
    if (sock < 0) return core.die(1, "udhcpd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_BROADCAST, &opt, @sizeOf(c_int));
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(DHCP_SERVER_PORT);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "udhcpd: bind (need root)\n", .{});

    const server_ip: u32 = 0xC0A80A01;
    const pool_start: u32 = 0xC0A80A14;
    const pool_end: u32 = 0xC0A80A4B;
    const netmask: u32 = 0xFFFFFF00;
    const lease_time: u32 = 3600;

    var next_ip = pool_start;
    var lease_file: ?c_int = null;

    core.writeAll(1, "udhcpd: listening on port 67\n");

    var buf: [2048]u8 = undefined;
    while (true) {
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const n = core.c.recvfrom(sock, &buf, buf.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
        if (n < @sizeOf(DhcpPacket) - 256) continue;

        const pkt: *DhcpPacket = @ptrCast(@alignCast(&buf));
        if (pkt.*.magic != 0x63825363) continue;

        var msg_type: u8 = 0;
        var optpos: usize = 0;
        while (optpos < 256) {
            const o = pkt.*.options[optpos];
            if (o == 255) break;
            if (o == 0) { optpos += 1; continue; }
            const olen = pkt.*.options[optpos + 1];
            if (o == 53 and olen > 0) msg_type = pkt.*.options[optpos + 2];
            optpos += 2 + olen;
        }

        if (msg_type == DHCP_DISCOVER) {
            var resp align(4) = std.mem.zeroes(DhcpPacket);
            resp.op = 2;
            resp.htype = 1;
            resp.hlen = 6;
            resp.xid = pkt.*.xid;
            resp.yiaddr = next_ip;
            resp.siaddr = server_ip;
            resp.magic = 0x63825363;
            @memcpy(resp.chaddr[0..6], pkt.*.chaddr[0..6]);

            var o: usize = 0;
            resp.options[o] = 53; o += 1; resp.options[o] = 1; o += 1; resp.options[o] = DHCP_OFFER; o += 1;
            resp.options[o] = 1; o += 1; resp.options[o] = 4; o += 1;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&netmask))[0..4]); o += 4;
            resp.options[o] = 3; o += 1; resp.options[o] = 4; o += 1;
            const router = server_ip;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&router))[0..4]); o += 4;
            resp.options[o] = 51; o += 1; resp.options[o] = 4; o += 1;
            const lt = core.c.htonl(lease_time);
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&lt))[0..4]); o += 4;
            resp.options[o] = 54; o += 1; resp.options[o] = 4; o += 1;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&server_ip))[0..4]); o += 4;
            resp.options[o] = 255; o += 1;

            var cli: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
            cli.sin_family = core.c.AF_INET;
            cli.sin_addr.s_addr = 0xFFFFFFFF;
            cli.sin_port = core.c.htons(DHCP_CLIENT_PORT);

            _ = core.c.sendto(sock, @as([*]u8, @ptrCast(&resp)), @sizeOf(DhcpPacket), 0,
                .{ .__sockaddr_in__ = @ptrCast(&cli) }, @sizeOf(@TypeOf(cli)));
        } else if (msg_type == DHCP_REQUEST) {
            var resp align(4) = std.mem.zeroes(DhcpPacket);
            resp.op = 2;
            resp.htype = 1;
            resp.hlen = 6;
            resp.xid = pkt.*.xid;
            resp.yiaddr = next_ip;
            resp.siaddr = server_ip;
            resp.magic = 0x63825363;
            @memcpy(resp.chaddr[0..6], pkt.*.chaddr[0..6]);

            var o: usize = 0;
            resp.options[o] = 53; o += 1; resp.options[o] = 1; o += 1; resp.options[o] = DHCP_ACK; o += 1;
            resp.options[o] = 1; o += 1; resp.options[o] = 4; o += 1;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&netmask))[0..4]); o += 4;
            resp.options[o] = 3; o += 1; resp.options[o] = 4; o += 1;
            const router = server_ip;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&router))[0..4]); o += 4;
            resp.options[o] = 51; o += 1; resp.options[o] = 4; o += 1;
            const lt = core.c.htonl(lease_time);
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&lt))[0..4]); o += 4;
            resp.options[o] = 54; o += 1; resp.options[o] = 4; o += 1;
            @memcpy(resp.options[o..o + 4], @as([*]const u8, @ptrCast(&server_ip))[0..4]); o += 4;
            resp.options[o] = 255; o += 1;

            var cli: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
            cli.sin_family = core.c.AF_INET;
            cli.sin_addr.s_addr = 0xFFFFFFFF;
            cli.sin_port = core.c.htons(DHCP_CLIENT_PORT);

            _ = core.c.sendto(sock, @as([*]u8, @ptrCast(&resp)), @sizeOf(DhcpPacket), 0,
                .{ .__sockaddr_in__ = @ptrCast(&cli) }, @sizeOf(@TypeOf(cli)));

            var ipbuf: [16]u8 = undefined;
            const ipb = @as([4]u8, @bitCast(next_ip));
            const ips = std.fmt.bufPrint(&ipbuf, "udhcpd: leased {d}.{d}.{d}.{d}\n", .{ ipb[0], ipb[1], ipb[2], ipb[3] }) catch "udhcpd: leased\n";
            core.writeAll(1, ips);

            const lf = alloc.dupeZ(u8, "/var/lib/dhcp/dhcpd.leases") catch continue;
            if (lf.len > 0) {
                lease_file = core.c.open(lf.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND, @as(c_uint, 0o644));
                if (lease_file) |lf2| {
                    var le: [128]u8 = undefined;
                    const le_s = std.fmt.bufPrint(&le, "{d} {d}\n", .{ core.c.time(null) + lease_time, @as(c_uint, next_ip) }) catch "";
                    if (le_s.len > 0) _ = core.c.write(lf2, le_s.ptr, le_s.len);
                    _ = core.c.close(lf2);
                }
            }

            if (next_ip < pool_end) {
                next_ip += 1;
            } else {
                next_ip = pool_start;
            }
        }
    }
}
