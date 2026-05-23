const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ifenslave", .main = main };

const SIOCBONDENSLAVE: c_ulong = 0x8990;
const SIOCBONDRELEASE: c_ulong = 0x8991;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: ifenslave MASTER SLAVE [SLAVE...]\n", .{});

    const master = args[1];
    const slaves = args[2..];

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "ifenslave: socket\n", .{});

    for (slaves) |slave| {
        var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
        const mn = @min(master.len, @as(usize, 15));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..mn], master[0..mn]);
        const sn = @min(slave.len, @as(usize, 15));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..sn], slave[0..sn]);

        if (core.c.ioctl(sock, SIOCBONDENSLAVE, &ifr) < 0) {
            core.eprint("ifenslave: cannot enslave {s}\n", .{slave});
            return 1;
        }
    }

    _ = core.c.close(sock);
    return 0;
}
