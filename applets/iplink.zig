const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "iplink", .main = main };

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.c.open("/proc/net/dev", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return 1;
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
            const val = std.fmt.parseInt(u64, f, 10) catch { idx += 1; continue; };
            switch (idx) {
                0 => rx_bytes = val,
                1 => rx_packets = val,
                8 => tx_bytes = val,
                9 => tx_packets = val,
                else => {},
            }
            idx += 1;
        }

        var out: [256]u8 = undefined;
        const l = std.fmt.bufPrint(&out, "{d}: {s} mtu 1500 qlen 1000\n    RX: {d} bytes {d} packets\n    TX: {d} bytes {d} packets\n",
            .{ 0, name, rx_bytes, rx_packets, tx_bytes, tx_packets },
        ) catch continue;
        core.writeAll(1, l);
    }
    return 0;
}
