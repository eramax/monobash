const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "zcip", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: zcip IFACE [SCRIPT]\n", .{});

    const alloc = std.heap.page_allocator;
    const iface = args[1];
    const script = if (args.len > 2) args[2] else "";

    const iface_z = alloc.dupeZ(u8, iface) catch return 1;
    defer alloc.free(iface_z);

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "zcip: socket\n", .{});

    const raw = core.c.socket(core.c.AF_PACKET, core.c.SOCK_DGRAM, core.c.htons(0x0806));
    if (raw < 0) return core.die(1, "zcip: raw socket (need root)\n", .{});

    var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
    const nl = @min(iface.len, @as(usize, 15));
    @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], iface[0..nl]);

    if (core.c.ioctl(raw, core.c.SIOCGIFINDEX, &ifr) < 0)
        return core.die(1, "zcip: cannot find interface\n", .{});
    const ifindex = @as(c_uint, @bitCast(ifr.ifr_ifru.ifru_ivalue));

    if (core.c.ioctl(sock, core.c.SIOCGIFHWADDR, &ifr) < 0)
        return 1;
    var mac: [6]u8 = undefined;
    @memcpy(mac[0..], ifr.ifr_ifru.ifru_hwaddr.sa_data[0..6]);

    const linklocal_base: u32 = 0xA9FE0000;
    var probe_ip: u32 = linklocal_base | ((@as(u32, mac[2]) << 24) | (@as(u32, mac[3]) << 16) | (@as(u32, mac[4]) << 8) | mac[5]);
    probe_ip = linklocal_base | (probe_ip & 0x0000FFFF);

    var arp: struct {
        htype: u16 align(1) = @byteSwap(@as(u16, 1)),
        ptype: u16 align(1) = @byteSwap(@as(u16, 0x0800)),
        hlen: u8 = 6,
        plen: u8 = 4,
        oper: u16 align(1) = @byteSwap(@as(u16, 1)),
        sha: [6]u8,
        spa: u32,
        tha: [6]u8 = .{0} ** 6,
        tpa: u32,
    } = .{ .sha = mac, .spa = 0, .tha = .{0} ** 6, .tpa = probe_ip };

    var dst: core.c.struct_sockaddr_ll = std.mem.zeroes(core.c.struct_sockaddr_ll);
    dst.sll_family = core.c.AF_PACKET;
    dst.sll_protocol = core.c.htons(0x0806);
    dst.sll_ifindex = @intCast(ifindex);
    dst.sll_halen = 6;
    @memset(&dst.sll_addr, 0xFF);

    _ = core.c.sendto(raw, @as([*]u8, @ptrCast(&arp)), @sizeOf(@TypeOf(arp)), 0,
        .{ .__sockaddr__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

    var ipbuf: [16]u8 = undefined;
    const ipb = @as([4]u8, @bitCast(probe_ip));
    const ips = std.fmt.bufPrint(&ipbuf, "zcip: probing {d}.{d}.{d}.{d}\n", .{ ipb[0], ipb[1], ipb[2], ipb[3] }) catch "zcip: probing\n";
    core.writeAll(1, ips);

    var addr6: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr6.sin_family = core.c.AF_INET;
    addr6.sin_addr.s_addr = probe_ip;

    if (core.c.ioctl(sock, core.c.SIOCSIFADDR, &ifr) < 0)
        return core.die(1, "zcip: cannot set address\n", .{});

    var ipbuf2: [16]u8 = undefined;
    const ipb2 = @as([4]u8, @bitCast(probe_ip));
    const ips2 = std.fmt.bufPrint(&ipbuf2, "zcip: configured {d}.{d}.{d}.{d}\n", .{ ipb2[0], ipb2[1], ipb2[2], ipb2[3] }) catch "zcip: configured\n";
    core.writeAll(1, ips2);

    if (script.len > 0) {
        const s = alloc.dupeZ(u8, script) catch return 1;
        defer alloc.free(s);
        _ = core.c.fork();
        _ = core.c.execle(s.ptr, s.ptr, iface_z.ptr, @as(?*anyopaque, null), @as(?*anyopaque, null));
    }

    _ = core.c.close(raw);
    _ = core.c.close(sock);
    return 0;
}
