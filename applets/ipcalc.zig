const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ipcalc", .main = main };

fn fmtIp(hex: u32, buf: *[16]u8) []u8 {
    const b = @as([4]u8, @bitCast(hex));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch buf[0..0];
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: ipcalc [-bnm] ADDRESS [NETMASK]\n", .{});
    const alloc = std.heap.page_allocator;

    var i: usize = 1;
    var opt_b = false;
    var opt_n = false;
    var opt_m = false;

    while (i < args.len and args[i][0] == '-') : (i += 1) {
        for (args[i][1..]) |c| {
            switch (c) {
                'b' => opt_b = true,
                'n' => opt_n = true,
                'm' => opt_m = true,
                else => return core.die(1, "ipcalc: unknown option\n", .{}),
            }
        }
    }
    if (i >= args.len) return core.die(1, "ipcalc: missing address\n", .{});

    const addr_str = args[i];
    i += 1;

    var prefix: u8 = 0;
    var addr_hex: u32 = 0;
    var netmask_hex: u32 = 0;

    if (std.mem.indexOfScalar(u8, addr_str, '/')) |sl| {
        const ip_part = addr_str[0..sl];
        const prefix_part = addr_str[sl + 1 ..];
        const ip_z = alloc.dupeZ(u8, ip_part) catch return 1;
        defer alloc.free(ip_z);
        addr_hex = core.c.inet_addr(ip_z.ptr);
        if (addr_hex == 0xFFFFFFFF) return core.die(1, "ipcalc: bad address\n", .{});
        prefix = std.fmt.parseInt(u8, prefix_part, 10) catch return core.die(1, "ipcalc: bad prefix\n", .{});
        netmask_hex = if (prefix == 0) 0 else ~@as(u32, 0) << @as(u5, @intCast(32 - prefix));
        netmask_hex = @byteSwap(netmask_hex);
    } else {
        const ip_z = alloc.dupeZ(u8, addr_str) catch return 1;
        defer alloc.free(ip_z);
        addr_hex = core.c.inet_addr(ip_z.ptr);
        if (addr_hex == 0xFFFFFFFF) return core.die(1, "ipcalc: bad address\n", .{});

        if (i < args.len) {
            const mask_z = alloc.dupeZ(u8, args[i]) catch return 1;
            defer alloc.free(mask_z);
            netmask_hex = @byteSwap(core.c.inet_addr(mask_z.ptr));
            if (netmask_hex == 0xFFFFFFFF) return core.die(1, "ipcalc: bad netmask\n", .{});
        } else {
            const a = @byteSwap(addr_hex);
            if (a & 0x80000000 != 0) {
                netmask_hex = if (a & 0x40000000 != 0) @byteSwap(@as(u32, 0xFFFFFF00)) else @byteSwap(@as(u32, 0xFFFF0000));
            } else {
                netmask_hex = @byteSwap(@as(u32, 0xFF000000));
            }
        }
    }

    const network = addr_hex & netmask_hex;
    const broadcast = network | ~netmask_hex;

    const mask_n = @byteSwap(netmask_hex);
    const pfx = 32 - @ctz(mask_n);

    var buf: [16]u8 = undefined;
    if (opt_m or (!opt_b and !opt_n)) {
        const s = std.fmt.allocPrint(alloc, "NETMASK={s}\n", .{fmtIp(netmask_hex, &buf)}) catch return 1;
        defer alloc.free(s);
        core.writeAll(1, s);
    }
    if (opt_n or (!opt_b and !opt_m)) {
        const s = std.fmt.allocPrint(alloc, "NETWORK={s}\n", .{fmtIp(network, &buf)}) catch return 1;
        defer alloc.free(s);
        core.writeAll(1, s);
    }
    if (opt_b or (!opt_n and !opt_m)) {
        const s = std.fmt.allocPrint(alloc, "BROADCAST={s}\n", .{fmtIp(broadcast, &buf)}) catch return 1;
        defer alloc.free(s);
        core.writeAll(1, s);
    }
    var pbuf: [32]u8 = undefined;
    const ps = std.fmt.bufPrint(&pbuf, "PREFIX={d}\n", .{pfx}) catch return 1;
    core.writeAll(1, ps);

    return 0;
}
