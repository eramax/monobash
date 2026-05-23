const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ifconfig", .main = main };

fn readFile(alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const fd = core.c.open(&buf, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 4096) catch null;
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n')) start += 1;
    var end = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n')) end -= 1;
    return s[start..end];
}

fn showIface(alloc: std.mem.Allocator, name: []const u8) void {
    const mac_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/address", .{name}) catch return;
    defer alloc.free(mac_path);
    const mac = readFile(alloc, mac_path);

    const flags_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/flags", .{name}) catch return;
    defer alloc.free(flags_path);
    const flags_raw = readFile(alloc, flags_path);

    var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
    const nlen = @min(name.len, @as(usize, ifr.ifr_ifrn.ifrn_name.len - 1));
    @memcpy(ifr.ifr_ifrn.ifrn_name[0..nlen], name[0..nlen]);

    const fd = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    var ip_str: []const u8 = "";
    var mask_str: []const u8 = "";
    if (fd >= 0) {
        if (core.c.ioctl(fd, core.c.SIOCGIFADDR, &ifr) == 0) {
            const sa: *core.c.struct_sockaddr_in = @ptrCast(&ifr.ifr_ifru.ifru_addr);
            const s = std.mem.sliceTo(core.c.inet_ntoa(sa.sin_addr), 0);
            ip_str = alloc.dupe(u8, s) catch "";
        }
        ifr = std.mem.zeroes(core.c.struct_ifreq);
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..nlen], name[0..nlen]);
        if (core.c.ioctl(fd, core.c.SIOCGIFNETMASK, &ifr) == 0) {
            const sa: *core.c.struct_sockaddr_in = @ptrCast(&ifr.ifr_ifru.ifru_netmask);
            const s = std.mem.sliceTo(core.c.inet_ntoa(sa.sin_addr), 0);
            mask_str = alloc.dupe(u8, s) catch "";
        }
        _ = core.c.close(fd);
    }

    core.writeAll(1, name);
    core.writeAll(1, "\n");

    if (mac) |m| {
        core.writeAll(1, "  MAC: ");
        core.writeAll(1, trim(m));
        core.writeAll(1, "\n");
        alloc.free(m);
    }

    if (flags_raw) |f| {
        core.writeAll(1, "  Flags: ");
        core.writeAll(1, trim(f));
        core.writeAll(1, "\n");
        alloc.free(f);
    }

    if (ip_str.len > 0) {
        core.writeAll(1, "  IP: ");
        core.writeAll(1, ip_str);
        if (mask_str.len > 0) {
            core.writeAll(1, "  Mask: ");
            core.writeAll(1, mask_str);
        }
        core.writeAll(1, "\n");
    }
}

fn listAll(alloc: std.mem.Allocator) void {
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
        const name = trim(line[0..colon]);
        if (name.len == 0) continue;

        const rest = line[colon + 1 ..];
        var fields = std.mem.splitScalar(u8, trim(rest), ' ');
        var field_idx: usize = 0;
        var rx_bytes: []const u8 = "";
        var tx_bytes: []const u8 = "";
        while (fields.next()) |field| {
            if (field.len == 0) continue;
            if (field_idx == 0) rx_bytes = field;
            if (field_idx == 8) tx_bytes = field;
            field_idx += 1;
        }

        const mac_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/address", .{name}) catch continue;
        defer alloc.free(mac_path);
        const mac = readFile(alloc, mac_path);
        defer if (mac) |m| alloc.free(m);

        var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
        const nl = @min(name.len, @as(usize, ifr.ifr_ifrn.ifrn_name.len - 1));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], name[0..nl]);

        const sfd = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
        var ip_str: []const u8 = "";
        if (sfd >= 0) {
            if (core.c.ioctl(sfd, core.c.SIOCGIFADDR, &ifr) == 0) {
                const sa: *core.c.struct_sockaddr_in = @ptrCast(&ifr.ifr_ifru.ifru_addr);
                ip_str = std.mem.sliceTo(core.c.inet_ntoa(sa.sin_addr), 0);
            }
            _ = core.c.close(sfd);
        }

        var out: [256]u8 = undefined;
        const line_str = std.fmt.bufPrint(&out, "{s:<8} IP {s:<15} MAC {s:<17} RX {s:<8} TX {s}\n",
            .{ name, ip_str, if (mac) |m| trim(m) else "", rx_bytes, tx_bytes },
        ) catch continue;
        core.writeAll(1, line_str);
    }
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "-")) {
        showIface(alloc, args[1]);
    } else {
        listAll(alloc);
    }
    return 0;
}
