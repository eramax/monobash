const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "nslookup", .main = main };

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: nslookup HOST\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "nslookup: unknown host\n", .{});

    core.writeAll(1, "Name: ");
    core.writeAll(1, host);
    core.writeAll(1, "\nAddresses:\n");

    var i: usize = 0;
    while (he.*.h_addr_list[i]) |addr| {
        var ina: core.c.struct_in_addr = undefined;
        ina.s_addr = netU32(addr);
        const s = std.mem.sliceTo(core.c.inet_ntoa(ina), 0);
        core.writeAll(1, "  ");
        core.writeAll(1, s);
        core.writeAll(1, "\n");
        i += 1;
    }
    return 0;
}
