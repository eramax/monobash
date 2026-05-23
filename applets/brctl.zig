const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "brctl", .main = main };

const SIOCBRADDBR: c_ulong = 0x89a0;
const SIOCBRDELBR: c_ulong = 0x89a1;
const SIOCBRADDIF: c_ulong = 0x89a2;
const SIOCBRDELIF: c_ulong = 0x89a3;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: brctl addbr|delbr|addif|delif BRIDGE [IFACE]\n", .{});
    const alloc = std.heap.page_allocator;
    const cmd = args[1];

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "brctl: socket\n", .{});

    if (std.mem.eql(u8, cmd, "addbr")) {
        if (args.len < 3) return core.die(1, "brctl: missing bridge name\n", .{});
        const name_z = alloc.dupeZ(u8, args[2]) catch return 1;
        defer alloc.free(name_z);
        if (core.c.ioctl(-1, SIOCBRADDBR, name_z.ptr) < 0)
            return core.die(1, "brctl: addbr failed\n", .{});
    } else if (std.mem.eql(u8, cmd, "delbr")) {
        if (args.len < 3) return core.die(1, "brctl: missing bridge name\n", .{});
        const name_z = alloc.dupeZ(u8, args[2]) catch return 1;
        defer alloc.free(name_z);
        if (core.c.ioctl(core.c.INT_MAX, SIOCBRDELBR, name_z.ptr) < 0)
            return core.die(1, "brctl: delbr failed\n", .{});
    } else if (std.mem.eql(u8, cmd, "addif") or std.mem.eql(u8, cmd, "delif")) {
        if (args.len < 4) return core.die(1, "brctl: missing bridge or interface name\n", .{});

        var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
        const ifname = args[3];
        const nl = @min(ifname.len, @as(usize, 15));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], ifname[0..nl]);

        const brname_z = alloc.dupeZ(u8, args[2]) catch return 1;
        defer alloc.free(brname_z);

        const br_idx = core.c.if_nametoindex(brname_z.ptr);
        if (br_idx == 0) return core.die(1, "brctl: bridge not found\n", .{});

        const ioctl_nr = if (std.mem.eql(u8, cmd, "addif")) SIOCBRADDIF else SIOCBRDELIF;

        var brifr: struct { [16]u8, c_int } = undefined;
        @memcpy(&brifr[0], ifr.ifr_ifrn.ifrn_name[0..16]);
        brifr[1] = @intCast(br_idx);

        if (core.c.ioctl(sock, ioctl_nr, &brifr) < 0)
            return core.die(1, "brctl: {s} failed\n", .{cmd});
    } else return core.die(1, "brctl: unknown command '{s}'\n", .{cmd});

    _ = core.c.close(sock);
    return 0;
}
