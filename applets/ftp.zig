const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ftp", .main = main };

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

fn recvResp(sock: c_int, buf: []u8) usize {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = core.c.recv(sock, buf.ptr + pos, buf.len - pos, 0);
        if (n <= 0) break;
        pos += @as(usize, @intCast(n));
        if (pos >= 4 and buf[pos - 1] == '\n' and buf[pos - 4] == ' ') break;
    }
    return pos;
}

fn sendCmd(sock: c_int, cmd: []const u8) void {
    _ = core.c.send(sock, cmd.ptr, cmd.len, 0);
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: ftp HOST\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "ftp: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(21);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "ftp: connection failed\n", .{});

    var buf: [4096]u8 = undefined;

    _ = recvResp(sock, &buf);
    sendCmd(sock, "USER anonymous\r\n");
    _ = recvResp(sock, &buf);
    sendCmd(sock, "PASS guest@\r\n");
    _ = recvResp(sock, &buf);

    sendCmd(sock, "PASV\r\n");
    const pasv_len = recvResp(sock, &buf);
    const pasv_str = buf[0..pasv_len];
    const paren_open = std.mem.indexOfScalar(u8, pasv_str, '(') orelse {
        core.writeAll(1, "ftp: PASV failed\n");
        core.writeAll(1, pasv_str);
        return 1;
    };
    const paren_close = std.mem.indexOfScalar(u8, pasv_str[paren_open..], ')') orelse return 1;
    const nums_str = pasv_str[paren_open + 1 .. paren_open + paren_close];
    var num_iter = std.mem.splitScalar(u8, nums_str, ',');

    _ = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;
    _ = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;
    _ = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;
    _ = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;
    const p1 = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;
    const p2 = std.fmt.parseInt(u8, num_iter.next() orelse return 1, 10) catch return 1;

    const data_port = (@as(u16, p1) << 8) | p2;

    const data_sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (data_sock < 0) return 1;
    defer _ = core.c.close(data_sock);

    var data_addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    data_addr.sin_family = core.c.AF_INET;
    data_addr.sin_addr.s_addr = netU32(ap);
    data_addr.sin_port = core.c.htons(data_port);

    if (core.c.connect(data_sock, .{ .__sockaddr_in__ = @ptrCast(&data_addr) }, @sizeOf(@TypeOf(data_addr))) < 0) {
        core.writeAll(1, "ftp: data connection failed\n");
        return 1;
    }

    sendCmd(sock, "LIST\r\n");
    _ = recvResp(sock, &buf);

    var list_buf: [8192]u8 = undefined;
    var list_pos: usize = 0;
    while (list_pos < list_buf.len) {
        const view = list_buf[list_pos..];
        const n = core.c.recv(data_sock, view.ptr, view.len, 0);
        if (n <= 0) break;
        list_pos += @as(usize, @intCast(n));
    }
    core.writeAll(1, list_buf[0..list_pos]);

    _ = recvResp(sock, &buf);
    sendCmd(sock, "QUIT\r\n");

    return 0;
}
