const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ipaddr", .main = main };

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

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const fd = core.c.opendir("/sys/class/net".ptr);
    if (fd == null) return 1;
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
    return 0;
}
