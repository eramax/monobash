const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sendmail", .main = main };

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

fn recvLine(sock: c_int, buf: []u8) usize {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = core.c.recv(sock, buf.ptr + pos, buf.len - pos, 0);
        if (n <= 0) break;
        pos += @as(usize, @intCast(n));
        if (pos >= 2 and buf[pos - 1] == '\n') break;
    }
    return pos;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 4) return core.die(1, "usage: sendmail -f FROM TO [TO...]\n", .{});

    const alloc = std.heap.page_allocator;
    var from: []const u8 = "";
    var to: [][]const u8 = undefined;
    var to_count: usize = 0;
    const server: []const u8 = "127.0.0.1";
    const port: u16 = 25;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-f") and i + 1 < args.len) {
            i += 1;
            from = args[i];
        } else {
            to = args[i..];
            to_count = args.len - i;
            break;
        }
    }

    if (from.len == 0 or to_count == 0) return core.die(1, "sendmail: missing from/to\n", .{});

    const server_z = alloc.dupeZ(u8, server) catch return 1;
    defer alloc.free(server_z);
    const he = core.c.gethostbyname(server_z.ptr) orelse return core.die(1, "sendmail: unknown server\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "sendmail: connection failed\n", .{});

    var buf: [4096]u8 = undefined;
    _ = recvLine(sock, &buf);

    const helo = alloc.dupeZ(u8, "localhost") catch return 1;
    defer alloc.free(helo);
    _ = core.c.send(sock, "HELO ", 5, 0);
    _ = core.c.send(sock, helo.ptr, helo.len, 0);
    _ = core.c.send(sock, "\r\n", 2, 0);
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "MAIL FROM:<", 11, 0);
    _ = core.c.send(sock, from.ptr, from.len, 0);
    _ = core.c.send(sock, ">\r\n", 3, 0);
    _ = recvLine(sock, &buf);

    for (0..to_count) |j| {
        _ = core.c.send(sock, "RCPT TO:<", 9, 0);
        _ = core.c.send(sock, to[j].ptr, to[j].len, 0);
        _ = core.c.send(sock, ">\r\n", 3, 0);
        _ = recvLine(sock, &buf);
    }

    _ = core.c.send(sock, "DATA\r\n", 6, 0);
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "From: ", 6, 0);
    _ = core.c.send(sock, from.ptr, from.len, 0);
    _ = core.c.send(sock, "\r\n", 2, 0);

    _ = core.c.send(sock, "To: ", 4, 0);
    for (0..to_count) |j| {
        _ = core.c.send(sock, to[j].ptr, to[j].len, 0);
        if (j + 1 < to_count) _ = core.c.send(sock, ", ", 2, 0);
    }
    _ = core.c.send(sock, "\r\n", 2, 0);
    _ = core.c.send(sock, "Subject: delivered by sendmail\r\n", 32, 0);
    _ = core.c.send(sock, "\r\n", 2, 0);

    if (i > 0) {
        const stdin_data = core.readAll(alloc, 0, 65536) catch "";
        if (stdin_data.len > 0) {
            _ = core.c.send(sock, stdin_data.ptr, stdin_data.len, 0);
        }
    }

    _ = core.c.send(sock, "\r\n.\r\n", 5, 0);
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "QUIT\r\n", 6, 0);
    return 0;
}
