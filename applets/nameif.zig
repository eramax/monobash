const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "nameif", .main = main };

const SIOCSIFNAME: c_ulong = 0x8923;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3 or (args.len - 1) % 2 != 0)
        return core.die(1, "usage: nameif IFNAME HWADDR [IFNAME HWADDR ...]\n", .{});

    var i: usize = 1;

    while (i + 1 < args.len) : (i += 2) {
        const newname = args[i];
        const hwaddr_str = args[i + 1];

        var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
        const nl = @min(newname.len, @as(usize, 15));
        @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], newname[0..nl]);

        var mac: [6]u8 = undefined;
        var hi: usize = 0;
        var hi_byte: u8 = 0;
        var byte_idx: usize = 0;

        for (hwaddr_str) |c| {
            if (c == ':') {
                if (hi > 0) mac[byte_idx] = hi_byte;
                byte_idx += 1;
                hi = 0;
                hi_byte = 0;
            } else {
                hi_byte = (hi_byte << 4) | (std.fmt.charToDigit(c, 16) catch 0);
                hi += 1;
            }
        }
        if (hi > 0 and byte_idx < 6) mac[byte_idx] = hi_byte;

        @memcpy(ifr.ifr_ifru.ifru_hwaddr.sa_data[0..6], &mac);
        ifr.ifr_ifru.ifru_hwaddr.sa_family = 1;

        const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
        if (sock < 0) return core.die(1, "nameif: socket\n", .{});

        if (core.c.ioctl(sock, SIOCSIFNAME, &ifr) < 0) {
            core.eprint("nameif: cannot rename to {s}\n", .{newname});
            _ = core.c.close(sock);
            return 1;
        }
        _ = core.c.close(sock);
    }

    return 0;
}
