const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lpq", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.htonl(@as(u32, 0x7F000001));
    addr.sin_port = core.c.htons(515);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "lpq: cannot connect to lpd\n", .{});

    const req = [2]u8{ 4, '\n' };
    _ = core.c.write(sock, &req, 2);

    var buf: [4096]u8 = undefined;
    const n = core.c.read(sock, &buf, buf.len);
    if (n > 0) core.writeAll(1, buf[0..@as(usize, @intCast(n))]);

    return 0;
}
