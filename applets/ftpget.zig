const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ftpget", .main = main };

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
    if (args.len < 3) return core.die(1, "usage: ftpget [-u USER] [-p PASS] [-P PORT] HOST REMOTE_FILE [LOCAL_FILE]\n", .{});

    const alloc = std.heap.page_allocator;
    var user: []const u8 = "anonymous";
    var pass: []const u8 = "guest@";
    var port: u16 = 21;
    var i: usize = 1;
    var host: []const u8 = "";
    var remote_file: []const u8 = "";
    var local_file: []const u8 = "";

    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-u") and i + 1 < args.len) { i += 1; user = args[i]; }
        else if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) { i += 1; pass = args[i]; }
        else if (std.mem.eql(u8, args[i], "-P") and i + 1 < args.len) { i += 1; port = std.fmt.parseInt(u16, args[i], 10) catch 21; }
        else if (host.len == 0) host = args[i]
        else if (remote_file.len == 0) remote_file = args[i]
        else local_file = args[i];
    }
    if (host.len == 0 or remote_file.len == 0) return core.die(1, "ftpget: missing host or remote file\n", .{});

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "ftpget: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "ftpget: connection failed\n", .{});

    var buf: [4096]u8 = undefined;
    _ = recvResp(sock, &buf);

    sendCmd(sock, "USER "); sendCmd(sock, user); sendCmd(sock, "\r\n");
    _ = recvResp(sock, &buf);
    sendCmd(sock, "PASS "); sendCmd(sock, pass); sendCmd(sock, "\r\n");
    _ = recvResp(sock, &buf);

    sendCmd(sock, "TYPE I\r\n");
    _ = recvResp(sock, &buf);

    sendCmd(sock, "PASV\r\n");
    const pasv_len = recvResp(sock, &buf);
    const pasv_str = buf[0..pasv_len];
    const paren_open = std.mem.indexOfScalar(u8, pasv_str, '(') orelse return core.die(1, "ftpget: PASV failed\n", .{});
    const paren_close = std.mem.indexOfScalar(u8, pasv_str[paren_open..], ')') orelse return 1;
    const nums_str = pasv_str[paren_open + 1 .. paren_open + paren_close];
    var num_iter = std.mem.splitScalar(u8, nums_str, ',');
    _ = num_iter.next(); _ = num_iter.next(); _ = num_iter.next(); _ = num_iter.next();
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

    if (core.c.connect(data_sock, .{ .__sockaddr_in__ = @ptrCast(&data_addr) }, @sizeOf(@TypeOf(data_addr))) < 0)
        return core.die(1, "ftpget: data connection failed\n", .{});

    sendCmd(sock, "RETR "); sendCmd(sock, remote_file); sendCmd(sock, "\r\n");
    _ = recvResp(sock, &buf);

    const out_fd = if (local_file.len > 0) blk: {
        const lf = alloc.dupeZ(u8, local_file) catch return 1;
        defer alloc.free(lf);
        break :blk core.c.open(lf.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    } else 1;

    if (out_fd < 0) return core.die(1, "ftpget: cannot open output file\n", .{});

    var recv_buf: [8192]u8 = undefined;
    while (true) {
        const n = core.c.recv(data_sock, &recv_buf, recv_buf.len, 0);
        if (n <= 0) break;
        core.writeAll(out_fd, recv_buf[0..@as(usize, @intCast(n))]);
    }

    if (out_fd != 1) _ = core.c.close(out_fd);
    _ = recvResp(sock, &buf);
    sendCmd(sock, "QUIT\r\n");
    return 0;
}
