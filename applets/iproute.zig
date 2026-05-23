const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "iproute", .main = main };

fn fmtIp(hex: u32, buf: *[16]u8) []u8 {
    const b = @as([4]u8, @bitCast(hex));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch buf[0..0];
}

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/proc/net/route", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return 1;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const iface = fields.next() orelse continue;
        const dst_hex = fields.next() orelse continue;
        const gw_hex = fields.next() orelse continue;
        _ = fields.next();
        _ = fields.next();
        _ = fields.next();
        _ = fields.next();
        const mask_hex = fields.next() orelse continue;

        const dst = std.fmt.parseInt(u32, dst_hex, 16) catch 0;
        const gw = std.fmt.parseInt(u32, gw_hex, 16) catch 0;
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
        }
    }
    return 0;
}
