const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "telnet", .main = main };

const IAC: u8 = 255;
const DONT: u8 = 254;
const DO: u8 = 253;
const WONT: u8 = 252;
const WILL: u8 = 251;

fn relay(client: c_int) void {
    var buf: [4096]u8 = undefined;
    var fds: [2]core.c.struct_pollfd = undefined;
    fds[0].fd = 0;
    fds[0].events = core.c.POLLIN;
    fds[1].fd = client;
    fds[1].events = core.c.POLLIN;

    while (true) {
        fds[0].revents = 0;
        fds[1].revents = 0;
        if (core.c.poll(&fds, 2, -1) < 0) break;

        if ((fds[0].revents & core.c.POLLIN) != 0) {
            const rn = core.c.read(0, &buf, buf.len);
            if (rn <= 0) break;
            _ = core.c.send(client, &buf, @as(usize, @intCast(rn)), 0);
        }
        if ((fds[1].revents & core.c.POLLIN) != 0) {
            const rn = core.c.recv(client, &buf, buf.len, 0);
            if (rn <= 0) break;

            var pos: usize = 0;
            var out_pos: usize = 0;
            var esc = false;

            while (pos < @as(usize, @intCast(rn))) {
                const b = buf[pos];
                if (esc) {
                    esc = false;
                    if (b == IAC) {
                        buf[out_pos] = IAC;
                        out_pos += 1;
                    } else if (b == DO or b == DONT) {
                        pos += 1;
                        if (pos < @as(usize, @intCast(rn))) {
                            const opt = buf[pos];
                            var resp: [3]u8 = undefined;
                            resp[0] = IAC;
                            resp[1] = if (b == DO) WONT else DONT;
                            resp[2] = opt;
                            _ = core.c.send(client, &resp, 3, 0);
                        }
                    } else if (b == WILL or b == WONT) {
                        pos += 1;
                        if (pos < @as(usize, @intCast(rn))) {
                            const opt = buf[pos];
                            var resp: [3]u8 = undefined;
                            resp[0] = IAC;
                            resp[1] = if (b == WILL) DONT else DONT;
                            resp[2] = opt;
                            _ = core.c.send(client, &resp, 3, 0);
                        }
                    }
                } else if (b == IAC) {
                    esc = true;
                } else {
                    buf[out_pos] = b;
                    out_pos += 1;
                }
                pos += 1;
            }
            if (out_pos > 0) {
                _ = core.c.write(1, &buf, out_pos);
            }
        }
    }
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: telnet HOST PORT\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const port = std.fmt.parseInt(u16, args[2], 10) catch
        return core.die(1, "telnet: invalid port\n", .{});

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "telnet: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "telnet: socket\n", .{});

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    var addr_bytes: [4]u8 = undefined;
    @memcpy(&addr_bytes, ap[0..4]);
    addr.sin_addr.s_addr = @as(u32, @bitCast(addr_bytes));
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "telnet: connection refused\n", .{});

    core.writeAll(1, "Connected to ");
    core.writeAll(1, host);
    core.writeAll(1, "\n");

    relay(sock);
    _ = core.c.close(sock);
    core.writeAll(1, "Connection closed.\n");
    return 0;
}
