const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ftpd", .main = main };

fn sendStr(fd: c_int, s: []const u8) void {
    _ = core.c.send(fd, s.ptr, s.len, 0);
}

fn recvLine(fd: c_int, buf: []u8) usize {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = core.c.recv(fd, buf.ptr + pos, 1, 0);
        if (n <= 0) break;
        if (buf[pos] == '\n') {
            pos += 1;
            break;
        }
        pos += 1;
    }
    return pos;
}

fn acceptData(pasv_sock: c_int) ?c_int {
    if (pasv_sock < 0) return null;
    var caddr: core.c.struct_sockaddr_in = undefined;
    var alen: core.c.socklen_t = @sizeOf(@TypeOf(caddr));
    const fd = core.c.accept(pasv_sock, .{ .__sockaddr_in__ = @ptrCast(&caddr) }, &alen);
    _ = core.c.close(pasv_sock);
    return if (fd >= 0) fd else null;
}

fn doList(control: c_int, data_sock: c_int) void {
    sendStr(control, "150 Opening data connection\r\n");

    const dir = core.c.opendir(".".ptr);
    if (dir == null) {
        core.writeAll(1, "ftpd: opendir failed\n");
        return;
    }
    defer _ = core.c.closedir(dir);

    while (true) {
        const dent = core.c.readdir(dir) orelse break;
        const name = std.mem.sliceTo(@as([*]u8, @ptrCast(&dent.*.d_name)), 0);
        if (name.len == 0 or (name.len == 1 and name[0] == '.') or (name.len == 2 and name[0] == '.' and name[1] == '.')) continue;

        var st: core.c.struct_stat = undefined;
        const name_z = std.heap.page_allocator.dupeZ(u8, name) catch continue;
        defer std.heap.page_allocator.free(name_z);
        const st_rc = core.c.stat(name_z.ptr, &st);
        const is_dir = st_rc == 0 and core.c.S_ISDIR(st.st_mode);
        const sz = if (st_rc == 0) st.st_size else 0;

        var line: [512]u8 = undefined;
        const l = std.fmt.bufPrint(&line, "{s}{s} {d}\r\n", .{ name, if (is_dir) "/" else "", sz }) catch continue;
        _ = core.c.send(data_sock, l.ptr, l.len, 0);
    }

    _ = core.c.close(data_sock);
    sendStr(control, "226 Directory send OK\r\n");
}

fn doRetr(control: c_int, data_sock: c_int, name: []const u8) void {
    const name_z = std.heap.page_allocator.dupeZ(u8, name) catch return;
    defer std.heap.page_allocator.free(name_z);
    const fd = core.c.open(name_z.ptr, core.c.O_RDONLY);
    if (fd < 0) {
        sendStr(control, "550 File not found\r\n");
        _ = core.c.close(data_sock);
        return;
    }
    defer _ = core.c.close(fd);

    sendStr(control, "150 Opening data connection\r\n");
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = core.c.read(fd, &buf, buf.len);
        if (n <= 0) break;
        _ = core.c.send(data_sock, &buf, @as(usize, @intCast(n)), 0);
    }
    _ = core.c.close(data_sock);
    sendStr(control, "226 Transfer complete\r\n");
}

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "ftpd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(21);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "ftpd: bind (need root for port 21)\n", .{});
    if (core.c.listen(sock, 5) < 0)
        return core.die(1, "ftpd: listen\n", .{});

    core.writeAll(1, "ftpd: listening on port 21\n");

    var pasv_sock: c_int = -1;
    var pasv_port: u16 = 0;
    var username: []const u8 = "";

    while (true) {
        var cli_addr: core.c.struct_sockaddr_in = undefined;
        var cli_len: core.c.socklen_t = @sizeOf(@TypeOf(cli_addr));
        const client = core.c.accept(sock, .{ .__sockaddr_in__ = @ptrCast(&cli_addr) }, &cli_len);
        if (client < 0) continue;

        sendStr(client, "220 FTP server ready\r\n");

        var buf: [4096]u8 = undefined;
        while (true) {
            const rlen = recvLine(client, &buf);
            if (rlen == 0) break;

            const line = std.mem.trim(u8, buf[0..rlen], "\r\n");
            if (line.len == 0) continue;

            const spc = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
            const cmd = line[0..spc];
            const arg = if (spc < line.len) std.mem.trim(u8, line[spc..], " ") else "";

            if (std.mem.eql(u8, cmd, "USER")) {
                username = alloc.dupe(u8, arg) catch "";
                sendStr(client, "230 Login successful\r\n");
            } else if (std.mem.eql(u8, cmd, "PASS")) {
                sendStr(client, "230 Login successful\r\n");
            } else if (std.mem.eql(u8, cmd, "SYST")) {
                sendStr(client, "215 UNIX Type: L8\r\n");
            } else if (std.mem.eql(u8, cmd, "PWD")) {
                sendStr(client, "257 \"/\" is current directory\r\n");
            } else if (std.mem.eql(u8, cmd, "CWD")) {
                sendStr(client, "250 Directory changed\r\n");
            } else if (std.mem.eql(u8, cmd, "TYPE")) {
                sendStr(client, "200 Type set\r\n");
            } else if (std.mem.eql(u8, cmd, "PASV")) {
                const psock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
                if (psock < 0) {
                    sendStr(client, "421 PASV failed\r\n");
                } else {
                    var opt2: c_int = 1;
                    _ = core.c.setsockopt(psock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt2, @sizeOf(c_int));
                    var paddr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
                    paddr.sin_family = core.c.AF_INET;
                    paddr.sin_port = core.c.htons(0);
                    paddr.sin_addr.s_addr = core.c.INADDR_ANY;
                    if (core.c.bind(psock, .{ .__sockaddr_in__ = @ptrCast(&paddr) }, @sizeOf(@TypeOf(paddr))) < 0 or
                        core.c.listen(psock, 1) < 0)
                    {
                        _ = core.c.close(psock);
                        sendStr(client, "421 PASV failed\r\n");
                    } else {
                        var ss: core.c.struct_sockaddr_in = undefined;
                        var sl: core.c.socklen_t = @sizeOf(@TypeOf(ss));
                        if (core.c.getsockname(psock, .{ .__sockaddr_in__ = @ptrCast(&ss) }, &sl) >= 0) {
                            pasv_port = core.c.ntohs(ss.sin_port);
                            pasv_sock = psock;
                            const ipb = @as([4]u8, @bitCast(cli_addr.sin_addr.s_addr));
                            var resp: [128]u8 = undefined;
                            const r = std.fmt.bufPrint(&resp, "227 Entering Passive Mode ({d},{d},{d},{d},{d},{d})\r\n",
                                .{ ipb[0], ipb[1], ipb[2], ipb[3], pasv_port >> 8, pasv_port & 0xFF },
                            ) catch {
                                sendStr(client, "421 PASV error\r\n");
                                continue;
                            };
                            sendStr(client, r);
                        } else {
                            _ = core.c.close(psock);
                            sendStr(client, "421 PASV failed\r\n");
                        }
                    }
                }
            } else if (std.mem.eql(u8, cmd, "LIST")) {
                if (pasv_sock < 0) {
                    sendStr(client, "425 Use PASV first\r\n");
                } else {
                    const ds = acceptData(pasv_sock);
                    pasv_sock = -1;
                    if (ds) |d| {
                        doList(client, d);
                    } else {
                        sendStr(client, "425 No data connection\r\n");
                    }
                }
            } else if (std.mem.eql(u8, cmd, "RETR")) {
                if (pasv_sock < 0) {
                    sendStr(client, "425 Use PASV first\r\n");
                } else if (arg.len == 0) {
                    sendStr(client, "501 Syntax error\r\n");
                } else {
                    const ds = acceptData(pasv_sock);
                    pasv_sock = -1;
                    if (ds) |d| {
                        doRetr(client, d, arg);
                    } else {
                        sendStr(client, "425 No data connection\r\n");
                    }
                }
            } else if (std.mem.eql(u8, cmd, "QUIT")) {
                sendStr(client, "221 Goodbye\r\n");
                break;
            } else {
                sendStr(client, "500 Unknown command\r\n");
            }
        }
        _ = core.c.close(client);
        if (pasv_sock >= 0) {
            _ = core.c.close(pasv_sock);
            pasv_sock = -1;
        }
    }
}
