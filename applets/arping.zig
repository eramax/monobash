const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "arping", .main = main };

const ETH_ALEN = 6;
const ETH_P_ARP = 0x0806;

fn writeU16be(buf: []u8, off: usize, v: u16) void {
    buf[off] = @as(u8, @intCast(v >> 8));
    buf[off + 1] = @as(u8, @intCast(v & 0xFF));
}

fn parseMac(s: []const u8, mac: *[6]u8) bool {
    var i: usize = 0;
    var octet: usize = 0;
    while (i < s.len and octet < 6) {
        const end = i + 2;
        if (end > s.len) return false;
        const val = std.fmt.parseInt(u8, s[i..end], 16) catch return false;
        mac[octet] = val;
        octet += 1;
        i = end;
        if (octet < 6 and i < s.len and s[i] == ':') i += 1;
    }
    return octet == 6;
}

fn readFileLine(path: []const u8) ?[]u8 {
    const alloc = std.heap.page_allocator;
    var p: [4096:0]u8 = undefined;
    if (path.len >= p.len) return null;
    @memcpy(p[0..path.len], path);
    p[path.len] = 0;
    const fd = core.c.open(&p, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 4096) catch return null;
    defer alloc.free(data);
    var i: usize = 0;
    while (i < data.len and data[i] != '\n' and data[i] != '\r') i += 1;
    return alloc.dupe(u8, data[0..i]) catch null;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var iface: []const u8 = "";
    var count: usize = 3;
    var target: []const u8 = "";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-I") and i + 1 < args.len) {
            i += 1;
            iface = args[i];
        } else if (std.mem.eql(u8, args[i], "-c") and i + 1 < args.len) {
            i += 1;
            count = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "arping: invalid count\n", .{});
        } else if (target.len == 0) {
            target = args[i];
        } else return core.die(1, "usage: arping -I IFACE -c N TARGET\n", .{});
    }
    if (iface.len == 0 or target.len == 0)
        return core.die(1, "usage: arping -I IFACE -c N TARGET\n", .{});

    const target_z = alloc.dupeZ(u8, target) catch return 1;
    defer alloc.free(target_z);
    const he = core.c.gethostbyname(target_z.ptr) orelse
        return core.die(1, "arping: unknown host\n", .{});
    const addr_list = he.*.h_addr_list;
    if (addr_list[0] == null) return 1;
    var target_ip: [4]u8 = undefined;
    @memcpy(&target_ip, addr_list[0][0..4]);

    const iface_z = alloc.dupeZ(u8, iface) catch return 1;
    defer alloc.free(iface_z);
    const ifindex = core.c.if_nametoindex(iface_z.ptr);
    if (ifindex == 0) return core.die(1, "arping: no such interface\n", .{});

    const mac_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/address", .{iface}) catch return 1;
    defer alloc.free(mac_path);
    const mac_str = readFileLine(mac_path) orelse return core.die(1, "arping: cannot get MAC\n", .{});
    defer alloc.free(mac_str);

    var src_mac: [6]u8 = undefined;
    if (!parseMac(mac_str, &src_mac)) return core.die(1, "arping: bad MAC\n", .{});

    const sock = core.c.socket(core.c.AF_PACKET, core.c.SOCK_RAW, core.c.htons(ETH_P_ARP));
    if (sock < 0) return core.die(1, "arping: socket (need root)\n", .{});
    defer _ = core.c.close(sock);

    var sll: core.c.struct_sockaddr_ll = std.mem.zeroes(core.c.struct_sockaddr_ll);
    sll.sll_family = core.c.AF_PACKET;
    sll.sll_ifindex = @as(c_int, @intCast(ifindex));
    sll.sll_protocol = core.c.htons(ETH_P_ARP);
    if (core.c.bind(sock, .{ .__sockaddr__ = @as([*c]const core.c.struct_sockaddr, @ptrCast(&sll)) }, @sizeOf(@TypeOf(sll))) < 0)
        return core.die(1, "arping: bind\n", .{});

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    const src_ip: [4]u8 = .{ 0, 0, 0, 0 };

    core.writeAll(1, "ARPING ");
    core.writeAll(1, target);
    core.writeAll(1, " from ");
    core.writeAll(1, iface);
    core.writeAll(1, "\n");

    var sent: usize = 0;
    var recv: usize = 0;

    for (0..count) |_| {
        var pkt: [42]u8 = undefined;
        @memset(&pkt, 0);

        @memcpy(pkt[0..6], &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });
        @memcpy(pkt[6..12], &src_mac);
        writeU16be(pkt[0..], 12, ETH_P_ARP);
        writeU16be(pkt[0..], 14, 1);
        writeU16be(pkt[0..], 16, 0x0800);
        pkt[18] = 6;
        pkt[19] = 4;
        writeU16be(pkt[0..], 20, 1);
        @memcpy(pkt[22..28], &src_mac);
        @memcpy(pkt[28..32], &src_ip);
        @memcpy(pkt[38..42], &target_ip);

        const n = core.c.sendto(sock, &pkt, pkt.len, 0, .{ .__sockaddr__ = @as([*c]const core.c.struct_sockaddr, @ptrCast(&sll)) }, @sizeOf(@TypeOf(sll)));
        if (n < 0) continue;
        sent += 1;

        var rbuf: [128]u8 = undefined;
        var from: core.c.struct_sockaddr_ll = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const rn = core.c.recvfrom(sock, &rbuf, rbuf.len, 0, .{ .__sockaddr__ = @as([*c]core.c.struct_sockaddr, @ptrCast(&from)) }, &fromlen);
        if (rn < @as(c_int, 42)) continue;

        const oper = (@as(u16, rbuf[20]) << 8) | rbuf[21];
        if (oper != 2) continue;

        recv += 1;
        var line: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&line, "ARP reply {d}.{d}.{d}.{d} [{x}:{x}:{x}:{x}:{x}:{x}] on {s}\n",
            .{ target_ip[0], target_ip[1], target_ip[2], target_ip[3],
               rbuf[22], rbuf[23], rbuf[24], rbuf[25], rbuf[26], rbuf[27],
               iface },
        ) catch continue;
        core.writeAll(1, msg);
    }

    var sum: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&sum, "Sent {d} probes ({d} broadcast(s))\nReceived {d} response(s)\n", .{ sent, sent, recv }) catch return 0;
    core.writeAll(1, s);
    return if (recv > 0) 0 else 1;
}
