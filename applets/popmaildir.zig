const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "popmaildir", .main = main };

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
    if (args.len < 3) return core.die(1, "usage: popmaildir HOST USER PASS\n", .{});

    const alloc = std.heap.page_allocator;
    const host = args[1];
    const user = args[2];
    const pass = args[3];

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "popmaildir: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(110);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "popmaildir: connection failed\n", .{});

    var buf: [4096]u8 = undefined;
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "USER ", 5, 0);
    _ = core.c.send(sock, user.ptr, user.len, 0);
    _ = core.c.send(sock, "\r\n", 2, 0);
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "PASS ", 5, 0);
    _ = core.c.send(sock, pass.ptr, pass.len, 0);
    _ = core.c.send(sock, "\r\n", 2, 0);
    _ = recvLine(sock, &buf);

    _ = core.c.send(sock, "STAT\r\n", 6, 0);
    const stat_len = recvLine(sock, &buf);
    const stat_line = buf[0..stat_len];
    core.writeAll(1, "popmaildir: ");
    core.writeAll(1, stat_line);

    _ = core.c.send(sock, "LIST\r\n", 6, 0);
    const list_len = recvLine(sock, &buf);
    const list_line = buf[0..list_len];

    var fields = std.mem.splitScalar(u8, list_line, ' ');
    _ = fields.next();
    if (fields.next()) |cnt_str| {
        const cnt = std.fmt.parseInt(u64, cnt_str, 10) catch 0;
        var msg: [64]u8 = undefined;
        const m = std.fmt.bufPrint(&msg, "popmaildir: {d} messages\n", .{cnt}) catch "popmaildir\n";
        core.writeAll(1, m);

        for (1..cnt + 1) |msgnum| {
            var cmd: [32]u8 = undefined;
            const c = std.fmt.bufPrint(&cmd, "RETR {d}\r\n", .{msgnum}) catch break;
            _ = core.c.send(sock, c.ptr, c.len, 0);

            var mbuf: [4096]u8 = undefined;
            var mpos: usize = 0;
            while (mpos < mbuf.len) {
                const n = core.c.recv(sock, mbuf[mpos..].ptr, mbuf.len - mpos, 0);
                _ = &n;
                if (n <= 0) break;
                mpos += @as(usize, @intCast(n));
                if (mpos >= 5 and mbuf[mpos - 1] == '\n' and mbuf[mpos - 5] == '.') break;
            }
            core.writeAll(1, mbuf[0..mpos]);
        }
    }

    _ = core.c.send(sock, "QUIT\r\n", 6, 0);
    return 0;
}
