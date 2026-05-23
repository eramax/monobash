const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "nc", .main = main };

fn relay(fd_in: c_int, fd_out: c_int, fd_rev: c_int) void {
    var buf: [4096]u8 = undefined;
    var fds: [2]core.c.struct_pollfd = undefined;
    fds[0].fd = fd_in;
    fds[0].events = core.c.POLLIN;
    fds[1].fd = fd_rev;
    fds[1].events = core.c.POLLIN;

    while (true) {
        fds[0].revents = 0;
        fds[1].revents = 0;
        if (core.c.poll(&fds, 2, -1) < 0) break;

        if ((fds[0].revents & core.c.POLLIN) != 0) {
            const rn = core.c.read(fd_in, &buf, buf.len);
            if (rn <= 0) break;
            _ = core.c.write(fd_out, &buf, @as(usize, @intCast(rn)));
        }
        if ((fds[1].revents & core.c.POLLIN) != 0) {
            const rn = core.c.read(fd_rev, &buf, buf.len);
            if (rn <= 0) break;
            _ = core.c.write(fd_in, &buf, @as(usize, @intCast(rn)));
        }
    }
}

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

fn run_client(host: []const u8, port: u16) u8 {
    const alloc = std.heap.page_allocator;
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "nc: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "nc: socket\n", .{});
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "nc: connection refused\n", .{});

    relay(0, sock, sock);
    return 0;
}

fn run_server(port: u16) u8 {
    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "nc: socket\n", .{});
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = 0;
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "nc: bind failed\n", .{});
    if (core.c.listen(sock, 1) < 0)
        return core.die(1, "nc: listen failed\n", .{});

    var client_addr: core.c.struct_sockaddr_in = undefined;
    var addrlen: core.c.socklen_t = @sizeOf(@TypeOf(client_addr));
    const client = core.c.accept(sock, .{ .__sockaddr_in__ = @ptrCast(&client_addr) }, &addrlen);
    if (client < 0) return core.die(1, "nc: accept failed\n", .{});
    defer _ = core.c.close(client);

    relay(0, client, client);
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var listen_mode = false;
    var host: ?[]const u8 = null;
    var port: u16 = 0;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-l")) {
            listen_mode = true;
        } else if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch
                return core.die(1, "nc: invalid port\n", .{});
        } else if (host == null) {
            host = args[i];
        } else {
            port = std.fmt.parseInt(u16, args[i], 10) catch
                return core.die(1, "nc: invalid port\n", .{});
        }
    }

    if (port == 0) return core.die(1, "usage: nc HOST PORT | nc -l -p PORT\n", .{});
    if (listen_mode) return run_server(port);
    return run_client(host orelse return core.die(1, "nc: host required\n", .{}), port);
}
