const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dhcprelay", .main = main };

const DHCP_SERVER_PORT: u16 = 67;
const DHCP_CLIENT_PORT: u16 = 68;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: dhcprelay IFACE IFACE...[SERVER]\n", .{});

    const alloc = std.heap.page_allocator;
    const server_if = args[1];
    const ifaces = args[2..];

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "dhcprelay: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_BROADCAST, &opt, @sizeOf(c_int));
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(DHCP_SERVER_PORT);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "dhcprelay: bind\n", .{});

    _ = core.c.close(sock);

    const fwd = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (fwd < 0) return core.die(1, "dhcprelay: socket\n", .{});
    _ = core.c.setsockopt(fwd, core.c.SOL_SOCKET, core.c.SO_BROADCAST, &opt, @sizeOf(c_int));

    const server_z = alloc.dupeZ(u8, server_if) catch return 1;
    defer alloc.free(server_z);
    const he = core.c.gethostbyname(server_z.ptr);
    var server_addr: u32 = undefined;
    if (he) |h| {
        const ap = h.*.h_addr_list[0] orelse return core.die(1, "dhcprelay: bad server\n", .{});
        var ab: [4]u8 = undefined;
        @memcpy(&ab, ap[0..4]);
        server_addr = @as(u32, @bitCast(ab));
    } else {
        server_addr = core.c.inet_addr(server_z.ptr);
        if (server_addr == 0xFFFFFFFF) return core.die(1, "dhcprelay: bad server\n", .{});
    }

    var buf: [2048]u8 = undefined;
    while (true) {
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const n = core.c.recvfrom(fwd, &buf, buf.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
        if (n <= 0) continue;

        var dst: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
        dst.sin_family = core.c.AF_INET;
        dst.sin_addr.s_addr = server_addr;
        dst.sin_port = core.c.htons(DHCP_SERVER_PORT);

        for (ifaces) |iface| {
            const iz = alloc.dupeZ(u8, iface) catch continue;
            defer alloc.free(iz);
            var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
            const nl = @min(iface.len, @as(usize, 15));
            @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], iface[0..nl]);
            if (core.c.ioctl(fwd, core.c.SIOCGIFADDR, &ifr) == 0) {
                const sa: *core.c.struct_sockaddr_in = @ptrCast(&ifr.ifr_ifru.ifru_addr);
                dst.sin_addr.s_addr = sa.sin_addr.s_addr;
            }
            _ = core.c.sendto(fwd, &buf, @as(usize, @intCast(n)), 0,
                .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));
        }
    }
}
