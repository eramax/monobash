const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dnsdomainname", .main = main };

pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    const fd = core.c.open("/etc/resolv.conf", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 4096) catch return 1;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "search ")) {
            const domain = std.mem.trim(u8, line["search ".len..], " \t");
            if (domain.len > 0) {
                core.writeAll(1, domain);
                core.writeAll(1, "\n");
                return 0;
            }
        }
        if (std.mem.startsWith(u8, line, "domain ")) {
            const domain = std.mem.trim(u8, line["domain ".len..], " \t");
            if (domain.len > 0) {
                core.writeAll(1, domain);
                core.writeAll(1, "\n");
                return 0;
            }
        }
    }
    return 0;
}
