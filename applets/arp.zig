const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "arp", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const fd = core.c.open("/proc/net/arp", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 65536) catch return 1;
    defer alloc.free(data);

    core.writeAll(1, "Address           HWtype   HWaddress               Flags   Mask            Iface\n");

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ' ');
        var ip: []const u8 = "";
        var hwtype: []const u8 = "";
        var flags: []const u8 = "";
        var hwaddr: []const u8 = "";
        var mask: []const u8 = "";
        var iface: []const u8 = "";
        var idx: usize = 0;

        while (fields.next()) |f| {
            if (f.len == 0) continue;
            switch (idx) {
                0 => ip = f,
                1 => hwtype = f,
                2 => flags = f,
                3 => hwaddr = f,
                4 => mask = f,
                5 => iface = f,
                else => {},
            }
            idx += 1;
        }

        var out: [256]u8 = undefined;
        const o = std.fmt.bufPrint(&out, "{s:<16} {s:<8} {s:<22} {s:<8} {s:<15} {s}\n",
            .{ ip, hwtype, hwaddr, flags, mask, iface },
        ) catch continue;
        core.writeAll(1, o);
    }

    return 0;
}
