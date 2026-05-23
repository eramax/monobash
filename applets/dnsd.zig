const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dnsd", .main = main };

const DNS_PORT: u16 = 53;
const MAX_PACK_LEN: usize = 512;
const DEFAULT_TTL: u32 = 120;

const Header = packed struct {
    id: u16,
    flags: u16,
    nquer: u16,
    nansw: u16,
    nauth: u16,
    nadd: u16,
};

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var port: u16 = DNS_PORT;
    var conf_file: []const u8 = "/etc/dnsd.conf";
    var ttl: u32 = DEFAULT_TTL;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) { i += 1; port = std.fmt.parseInt(u16, args[i], 10) catch DNS_PORT; }
        else if (std.mem.eql(u8, args[i], "-c") and i + 1 < args.len) { i += 1; conf_file = args[i]; }
        else if (std.mem.eql(u8, args[i], "-t") and i + 1 < args.len) { i += 1; ttl = std.fmt.parseInt(u32, args[i], 10) catch DEFAULT_TTL; }
        else if (std.mem.eql(u8, args[i], "-d")) {}
        else if (std.mem.eql(u8, args[i], "-v")) {}
    }

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "dnsd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "dnsd: bind (need root)\n", .{});

    var cf_buf: [4096]u8 = undefined;
    _ = &cf_buf;
    var hosts: [64]struct { name: []u8, ip: u32 } = undefined;
    var host_count: usize = 0;

    const cf_z = alloc.dupeZ(u8, conf_file) catch return 1;
    defer alloc.free(cf_z);
    const cf = core.c.open(cf_z.ptr, core.c.O_RDONLY);
    if (cf >= 0) {
        defer _ = core.c.close(cf);
        const data = core.readAll(alloc, cf, 4096) catch "";
        if (data.len > 0) {
            var lines = std.mem.splitScalar(u8, data, '\n');
            while (lines.next()) |line| {
                if (line.len == 0 or line[0] == '#') continue;
                var fields = std.mem.splitScalar(u8, line, ' ');
                const ip_str = fields.next() orelse continue;
                const name_str = fields.next() orelse continue;
                const ip_z = alloc.dupeZ(u8, ip_str) catch continue;
                defer alloc.free(ip_z);
                const ip = core.c.inet_addr(ip_z.ptr);
                if (ip == 0xFFFFFFFF) continue;
                if (host_count < hosts.len) {
                    hosts[host_count] = .{ .name = alloc.dupe(u8, name_str) catch continue, .ip = ip };
                    host_count += 1;
                }
            }
        }
        alloc.free(data);
    }

    var pkt: [MAX_PACK_LEN]u8 = undefined;
    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "dnsd: listening on port {d}\n", .{port}) catch "dnsd: listening\n";
    core.writeAll(1, m);

    while (true) {
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const n = core.c.recvfrom(sock, &pkt, pkt.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
        if (n < 12) continue;

        const hdr = @as(*Header, @ptrCast(@alignCast(&pkt)));
        const nquer = core.c.ntohs(hdr.*.nquer);
        if (nquer == 0) continue;

        var pos: usize = 12;
        var qname: [256]u8 = undefined;
        var qpos: usize = 0;

        while (pos < @as(usize, @intCast(n))) {
            const label_len = pkt[pos];
            if (label_len == 0) { pos += 1; break; }
            if (label_len & 0xC0 != 0) { pos += 2; break; }
            pos += 1;
            if (qpos > 0) { qname[qpos] = '.'; qpos += 1; }
            for (0..label_len) |j| {
                qname[qpos] = std.ascii.toLower(pkt[pos + j]);
                qpos += 1;
            }
            pos += label_len;
        }
        const name = qname[0..qpos];

        if (pos + 4 > @as(usize, @intCast(n))) continue;
        const qtype = (@as(u16, pkt[pos]) << 8) | pkt[pos + 1];
        pos += 4;

        if (qtype != 1) continue;

        var found_ip: ?u32 = null;
        for (0..host_count) |j| {
            if (std.mem.eql(u8, name, hosts[j].name)) {
                found_ip = hosts[j].ip;
                break;
            }
        }

        const resp_len = @as(usize, @intCast(n));
        hdr.*.flags = core.c.htons(@as(u16, 0x8000));
        hdr.*.nansw = if (found_ip != null) core.c.htons(1) else 0;

        if (found_ip) |ip| {
            const ans_off = resp_len;
            const ans_end = ans_off + 16;
            if (ans_end > pkt.len) continue;

            @memset(pkt[ans_off..ans_end], 0);
            pkt[ans_off] = 0xC0;
            pkt[ans_off + 1] = 12;
            pkt[ans_off + 2] = 0x00;
            pkt[ans_off + 3] = 0x01;
            pkt[ans_off + 4] = 0x00;
            pkt[ans_off + 5] = 0x01;
            const ttl_net = core.c.htonl(ttl);
            @memcpy(pkt[ans_off + 6 .. ans_off + 10], @as([*]const u8, @ptrCast(&ttl_net))[0..4]);
            pkt[ans_off + 10] = 0x00;
            pkt[ans_off + 11] = 0x04;
            @memcpy(pkt[ans_off + 12 .. ans_off + 16], @as([*]const u8, @ptrCast(&ip))[0..4]);

            _ = core.c.sendto(sock, &pkt, ans_end, 0,
                .{ .__sockaddr_in__ = @ptrCast(&from) }, fromlen);
        } else {
            _ = core.c.sendto(sock, &pkt, resp_len, 0,
                .{ .__sockaddr_in__ = @ptrCast(&from) }, fromlen);
        }
    }
}
