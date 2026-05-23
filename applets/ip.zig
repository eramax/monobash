const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ip", .main = main };

fn fmtIp(hex: u32, buf: *[16]u8) []u8 {
    const b = @as([4]u8, @bitCast(hex));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch buf[0..0];
}

fn fmtMac(s: []const u8) void {
    core.writeAll(1, s);
}

fn readFile(alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    var p: [4096:0]u8 = undefined;
    if (path.len >= p.len) return null;
    @memcpy(p[0..path.len], path);
    p[path.len] = 0;
    const fd = core.c.open(&p, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 65536) catch null;
}

fn readLine(alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
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
    while (i > 0 and (data[i - 1] == ' ' or data[i - 1] == '\t')) i -= 1;
    return alloc.dupe(u8, data[0..i]) catch null;
}

fn cmdAddr(alloc: std.mem.Allocator) void {
    const fd = core.c.opendir("/sys/class/net".ptr);
    if (fd == null) return;
    defer _ = core.c.closedir(fd);

    while (true) {
        const dent = core.c.readdir(fd) orelse break;
        const name = std.mem.sliceTo(@as([*]u8, @ptrCast(&dent.*.d_name)), 0);
        if (name.len == 0 or (name.len == 1 and name[0] == '.') or (name.len == 2 and name[0] == '.' and name[1] == '.')) continue;

        const flags_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/flags", .{name}) catch continue;
        defer alloc.free(flags_path);
        const flags_s = readLine(alloc, flags_path);
        defer if (flags_s) |f| alloc.free(f);
        const flags = if (flags_s) |f| std.fmt.parseInt(u32, f, 16) catch 0 else 0;
        const up = (flags & 1) != 0;

        const mac_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/address", .{name}) catch continue;
        defer alloc.free(mac_path);
        const mac = readLine(alloc, mac_path);
        defer if (mac) |m| alloc.free(m);

        var out: [256]u8 = undefined;
        const state = if (up) "UP" else "DOWN";
        const l = std.fmt.bufPrint(&out, "{d}: {s}: <{s}> mtu 1500 state {s}\n    link/ether {s}\n",
            .{ 0, name, if (up) "UP,BROADCAST,RUNNING,MULTICAST" else "BROADCAST,MULTICAST", state, if (mac) |m| m else "" },
        ) catch continue;
        core.writeAll(1, l);

        var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
        const nl = @min(name.len, @as(usize, ifr.ifr_ifrn.ifrn_name.len - 1));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], name[0..nl]);

        const sfd = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
        if (sfd >= 0) {
            if (core.c.ioctl(sfd, core.c.SIOCGIFADDR, &ifr) == 0) {
                const sa: *core.c.struct_sockaddr_in = @ptrCast(&ifr.ifr_ifru.ifru_addr);
                const s = std.mem.sliceTo(core.c.inet_ntoa(sa.sin_addr), 0);
                var buf: [128]u8 = undefined;
                const a = std.fmt.bufPrint(&buf, "    inet {s}\n", .{s}) catch continue;
                core.writeAll(1, a);
            }
            _ = core.c.close(sfd);
        }
    }
}

fn cmdLink(alloc: std.mem.Allocator) void {
    const fd = core.c.open("/proc/net/dev", core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    _ = lines.next();

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " ");
        if (name.len == 0) continue;

        var fields = std.mem.splitScalar(u8, std.mem.trim(u8, line[colon + 1 ..], " "), ' ');
        var idx: usize = 0;
        var rx_bytes: u64 = 0;
        var rx_packets: u64 = 0;
        var tx_bytes: u64 = 0;
        var tx_packets: u64 = 0;
        while (fields.next()) |f| {
            const val = std.fmt.parseInt(u64, f, 10) catch {
                idx += 1;
                continue;
            };
            switch (idx) {
                0 => rx_bytes = val,
                1 => rx_packets = val,
                8 => tx_bytes = val,
                9 => tx_packets = val,
                else => {},
            }
            idx += 1;
        }

        const flags_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/flags", .{name}) catch continue;
        defer alloc.free(flags_path);
        const flags_s = readLine(alloc, flags_path);
        defer if (flags_s) |f| alloc.free(f);
        const flags = if (flags_s) |f| std.fmt.parseInt(u32, f, 16) catch 0 else 0;
        const up = (flags & 1) != 0;

        var out: [256]u8 = undefined;
        const l = std.fmt.bufPrint(&out, "{d}: {s} mtu 1500 state {s} qlen 1000\n    RX: {d} bytes {d} packets\n    TX: {d} bytes {d} packets\n",
            .{ 0, name, if (up) "UP" else "DOWN", rx_bytes, rx_packets, tx_bytes, tx_packets },
        ) catch continue;
        core.writeAll(1, l);
    }
}

fn cmdRoute(alloc: std.mem.Allocator) void {
    const fd = core.c.open("/proc/net/route", core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const iface = fields.next() orelse continue;
        const dst_hex = fields.next() orelse continue;
        const gw_hex = fields.next() orelse continue;
        const flags_hex = fields.next() orelse continue;
        _ = fields.next();
        _ = fields.next();
        _ = fields.next();
        const mask_hex = fields.next() orelse continue;

        const dst = std.fmt.parseInt(u32, dst_hex, 16) catch 0;
        const gw = std.fmt.parseInt(u32, gw_hex, 16) catch 0;
        const flags = std.fmt.parseInt(u32, flags_hex, 16) catch 0;
        const mask = std.fmt.parseInt(u32, mask_hex, 16) catch 0;

        var dbuf: [16]u8 = undefined;
        var gbuf: [16]u8 = undefined;

        if (dst == 0 and mask == 0) {
            var out: [128]u8 = undefined;
            const o = std.fmt.bufPrint(&out, "default via {s} dev {s}\n", .{ fmtIp(gw, &gbuf), iface }) catch continue;
            core.writeAll(1, o);
        } else {
            var out: [128]u8 = undefined;
            const o = std.fmt.bufPrint(&out, "{s}/{d} dev {s} proto kernel\n",
                .{ fmtIp(dst, &dbuf), @popCount(mask), iface },
            ) catch continue;
            core.writeAll(1, o);
            if (gw != 0 and (flags & 2) != 0) {
                var out2: [128]u8 = undefined;
                const o2 = std.fmt.bufPrint(&out2, "    via {s}\n", .{fmtIp(gw, &gbuf)}) catch continue;
                core.writeAll(1, o2);
            }
        }
    }
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    if (args.len < 2) return core.die(1, "usage: ip <addr|link|route>\n", .{});

    const sub = args[1];
    if (std.mem.eql(u8, sub, "addr")) {
        cmdAddr(alloc);
    } else if (std.mem.eql(u8, sub, "link")) {
        cmdLink(alloc);
    } else if (std.mem.eql(u8, sub, "route")) {
        cmdRoute(alloc);
    } else return core.die(1, "ip: unknown subcommand '{s}'\n", .{sub});

    return 0;
}
