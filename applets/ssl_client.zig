const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ssl_client", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: ssl_client HOST [PORT]\n", .{});

    const alloc = std.heap.page_allocator;
    const host = args[1];
    const port = if (args.len > 2) std.fmt.parseInt(u16, args[2], 10) catch 443 else 443;

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "ssl_client: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    var addr_bytes: [4]u8 = undefined;
    @memcpy(&addr_bytes, ap[0..4]);
    addr.sin_addr.s_addr = @as(u32, @bitCast(addr_bytes));
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "ssl_client: connection failed\n", .{});

    core.writeAll(1, "ssl_client: connected (raw tunnel)\n");

    var buf: [16384]u8 = undefined;
    while (true) {
        var poll_fds: [2]core.c.struct_pollfd = undefined;
        poll_fds[0].fd = 0;
        poll_fds[0].events = core.c.POLLIN;
        poll_fds[1].fd = sock;
        poll_fds[1].events = core.c.POLLIN;

        const rc = core.c.poll(&poll_fds, 2, -1);
        if (rc < 0) break;

        if ((poll_fds[0].revents & core.c.POLLIN) != 0) {
            const n = core.c.read(0, &buf, buf.len);
            if (n <= 0) break;
            _ = core.c.send(sock, &buf, @as(usize, @intCast(n)), 0);
        }
        if ((poll_fds[1].revents & core.c.POLLIN) != 0) {
            const n = core.c.recv(sock, &buf, buf.len, 0);
            if (n <= 0) break;
            _ = core.c.write(1, &buf, @as(usize, @intCast(n)));
        }
    }

    _ = core.c.close(sock);
    return 0;
}
