const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "route", .main = main };

fn fmtIp(hex: u32, buf: *[16]u8) []u8 {
    const b = @as([4]u8, @bitCast(hex));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch buf[0..0];
}

fn fmtFlags(flags: u32, buf: *[4]u8) []u8 {
    const u = (flags & 1) != 0;
    const g = (flags & 2) != 0;
    return std.fmt.bufPrint(buf, "{s}{s} ", .{
        if (u) "U" else " ",
        if (g) "G" else " ",
    }) catch buf[0..0];
}

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const fd = core.c.open("/proc/net/route", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 65536) catch return 1;
    defer alloc.free(data);

    core.writeAll(1, "Iface   Destination     Gateway         Flags   RefCnt  Use     Metric  Mask            MTU     Window  IRTT\n");

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const iface = fields.next() orelse continue;
        const dest_hex = fields.next() orelse continue;
        const gw_hex = fields.next() orelse continue;
        const flags_hex = fields.next() orelse continue;
        const refcnt = fields.next() orelse continue;
        const use_f = fields.next() orelse continue;
        const metric = fields.next() orelse continue;
        const mask_hex = fields.next() orelse continue;
        const mtu = fields.next() orelse continue;
        const window = fields.next() orelse continue;
        const irtt = fields.next() orelse continue;

        const dest = std.fmt.parseInt(u32, dest_hex, 16) catch 0;
        const gw = std.fmt.parseInt(u32, gw_hex, 16) catch 0;
        const flags = std.fmt.parseInt(u32, flags_hex, 16) catch 0;
        const mask = std.fmt.parseInt(u32, mask_hex, 16) catch 0;

        var ipbuf: [16]u8 = undefined;
        var gbuf: [16]u8 = undefined;
        var mbuf: [16]u8 = undefined;
        var fbuf: [4]u8 = undefined;

        var out: [256]u8 = undefined;
        const o = std.fmt.bufPrint(&out,
            "{s:<7} {s:<15} {s:<15} {s:<4} {s:<7} {s:<7} {s:<7} {s:<15} {s:<7} {s:<7} {s}\n",
            .{
                iface,
                fmtIp(dest, &ipbuf),
                fmtIp(gw, &gbuf),
                fmtFlags(flags, &fbuf),
                refcnt, use_f, metric,
                fmtIp(mask, &mbuf),
                mtu, window, irtt,
            },
        ) catch continue;
        core.writeAll(1, o);
    }

    return 0;
}
