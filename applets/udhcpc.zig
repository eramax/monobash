const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "udhcpc", .main = main };

const DHCP_DISCOVER: u8 = 1;
const DHCP_OFFER: u8 = 2;
const DHCP_REQUEST: u8 = 3;
const DHCP_ACK: u8 = 5;
const DHCP_NAK: u8 = 6;
const DHCP_RELEASE: u8 = 7;
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
    const alloc = std.heap.page_allocator;
    var iface: []const u8 = "eth0";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-i") and i + 1 < args.len) { i += 1; iface = args[i]; }
    }

    const iface_z = alloc.dupeZ(u8, iface) catch return 1;
    defer alloc.free(iface_z);

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, core.c.IPPROTO_UDP);
    if (sock < 0) return core.die(1, "udhcpc: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_BROADCAST, &opt, @sizeOf(c_int));
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var cli: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    cli.sin_family = core.c.AF_INET;
    cli.sin_addr.s_addr = core.c.INADDR_ANY;
    cli.sin_port = core.c.htons(DHCP_CLIENT_PORT);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&cli) }, @sizeOf(@TypeOf(cli))) < 0)
        return core.die(1, "udhcpc: bind\n", .{});

    var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
    const nl = @min(iface.len, @as(usize, 15));
    @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], iface[0..nl]);

    _ = core.c.ioctl(sock, core.c.SIOCGIFHWADDR, &ifr);
    var mac: [6]u8 = undefined;
    @memcpy(mac[0..], ifr.ifr_ifru.ifru_hwaddr.sa_data[0..6]);

    const xid: u32 = @intCast(core.c.getpid());
    var pkt align(4) = std.mem.zeroes(DhcpPacket);

    pkt.op = 1;
    pkt.htype = 1;
    pkt.hlen = 6;
    pkt.xid = xid;
    @memcpy(pkt.chaddr[0..6], &mac);
    pkt.magic = 0x63825363;

    var opts: usize = 0;
    pkt.options[opts] = 53; opts += 1; pkt.options[opts] = 1; opts += 1; pkt.options[opts] = DHCP_DISCOVER; opts += 1;
    pkt.options[opts] = 55; opts += 1; pkt.options[opts] = 3; opts += 1;
    pkt.options[opts] = 1; opts += 1; pkt.options[opts] = 3; opts += 1; pkt.options[opts] = 6; opts += 1;
    pkt.options[opts] = 255; opts += 1;
    pkt.options[opts] = 0; opts += 1;

    var dst: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    dst.sin_family = core.c.AF_INET;
    dst.sin_addr.s_addr = 0xFFFFFFFF;
    dst.sin_port = core.c.htons(DHCP_SERVER_PORT);

    _ = core.c.sendto(sock, @as([*]u8, @ptrCast(&pkt)), @sizeOf(DhcpPacket), 0,
        .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

    core.writeAll(1, "udhcpc: discover sent\n");

    var tv: core.c.struct_timeval = .{ .tv_sec = 5, .tv_usec = 0 };
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var resp: [2048]u8 = undefined;
    var from: core.c.struct_sockaddr_in = undefined;
    var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
    const n = core.c.recvfrom(sock, &resp, resp.len, 0,
        .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);

    if (n < @sizeOf(DhcpPacket) - 256) return core.die(1, "udhcpc: no response\n", .{});

    const rpkt: *DhcpPacket = @ptrCast(@alignCast(&resp));
    const yiaddr = rpkt.*.yiaddr;

    var ipbuf: [16]u8 = undefined;
    const ipb = @as([4]u8, @bitCast(yiaddr));
    const ips = std.fmt.bufPrint(&ipbuf, "{d}.{d}.{d}.{d}", .{ ipb[0], ipb[1], ipb[2], ipb[3] }) catch "?.?.?.?";
    core.writeAll(1, "udhcpc: got address ");
    core.writeAll(1, ips);
    core.writeAll(1, "\n");

    var pkt2 align(4) = std.mem.zeroes(DhcpPacket);
    pkt2.op = 1;
    pkt2.htype = 1;
    pkt2.hlen = 6;
    pkt2.xid = xid;
    pkt2.ciaddr = yiaddr;
    @memcpy(pkt2.chaddr[0..6], &mac);
    pkt2.magic = 0x63825363;

    opts = 0;
    pkt2.options[opts] = 53; opts += 1; pkt2.options[opts] = 1; opts += 1; pkt2.options[opts] = DHCP_REQUEST; opts += 1;
    pkt2.options[opts] = 50; opts += 1; pkt2.options[opts] = 4; opts += 1;
    @memcpy(pkt2.options[opts..opts + 4], @as([*]const u8, @ptrCast(&yiaddr))[0..4]); opts += 4;
    pkt2.options[opts] = 255; opts += 1;
    pkt2.options[opts] = 0; opts += 1;

    _ = core.c.sendto(sock, @as([*]u8, @ptrCast(&pkt2)), @sizeOf(DhcpPacket), 0,
        .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

    core.writeAll(1, "udhcpc: request sent\n");

    return 0;
}
