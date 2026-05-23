const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ftpput", .main = main };

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
    if (args.len < 3) return core.die(1, "usage: ftpput [-u USER] [-p PASS] [-P PORT] HOST [REMOTE_FILE] LOCAL_FILE\n", .{});

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
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) { i += 1; pass = args[i]; }
        if (std.mem.eql(u8, args[i], "-P") and i + 1 < args.len) { i += 1; port = std.fmt.parseInt(u16, args[i], 10) catch 21; }
        if (host.len == 0) { host = args[i]; continue; }
        if (remote_file.len == 0) { remote_file = args[i]; continue; }
        local_file = args[i];
    }
    if (host.len == 0 or local_file.len == 0) return core.die(1, "ftpput: missing host or local file\n", .{});
    if (remote_file.len == 0) { remote_file = local_file; }

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "ftpput: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "ftpput: connection failed\n", .{});

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
    const paren_open = std.mem.indexOfScalar(u8, pasv_str, '(') orelse return core.die(1, "ftpput: PASV failed\n", .{});
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
        return core.die(1, "ftpput: data connection failed\n", .{});

    const lf = alloc.dupeZ(u8, local_file) catch return 1;
    defer alloc.free(lf);
    const in_fd = core.c.open(lf.ptr, core.c.O_RDONLY);
    if (in_fd < 0) return core.die(1, "ftpput: cannot open local file\n", .{});

    sendCmd(sock, "STOR "); sendCmd(sock, remote_file); sendCmd(sock, "\r\n");
    _ = recvResp(sock, &buf);

    const file_data = core.readAll(alloc, in_fd, 32 * 1024 * 1024) catch return 1;
    defer alloc.free(file_data);
    var pos: usize = 0;
    while (pos < file_data.len) {
        const n = @min(8192, file_data.len - pos);
        _ = core.c.send(data_sock, file_data.ptr + pos, n, 0);
        pos += n;
    }

    _ = core.c.close(in_fd);
    _ = recvResp(sock, &buf);
    sendCmd(sock, "QUIT\r\n");
    return 0;
}
