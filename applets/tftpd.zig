const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tftpd", .main = main };

const TFTP_PORT: u16 = 69;
const OP_RRQ: u16 = 1;
const OP_WRQ: u16 = 2;
const OP_DATA: u16 = 3;
const OP_ACK: u16 = 4;
const OP_ERR: u16 = 5;

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var dir: []const u8 = ".";
    var port: u16 = TFTP_PORT;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) { i += 1; port = std.fmt.parseInt(u16, args[i], 10) catch TFTP_PORT; }
        else dir = args[i];
    }

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "tftpd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "tftpd: bind (need root)\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "tftpd: listening on port {d}, root {s}\n", .{ port, dir }) catch "tftpd: started\n";
    core.writeAll(1, m);

    var buf: [2048]u8 = undefined;
    while (true) {
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const n = core.c.recvfrom(sock, &buf, buf.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
        if (n < 4) continue;

        const opcode = core.c.ntohs(@as(u16, @bitCast(buf[0..2].*)));
        const filename_end = std.mem.indexOfScalar(u8, buf[2..@as(usize, @intCast(n))], 0) orelse continue;
        const filename = buf[2..2 + filename_end];

        if (opcode == OP_RRQ) {
            const fpath = std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir, filename }) catch continue;
            defer alloc.free(fpath);
            const fz = alloc.dupeZ(u8, fpath) catch continue;
            defer alloc.free(fz);

            const fd = core.c.open(fz.ptr, core.c.O_RDONLY);
            if (fd < 0) {
                var err: [4 + 2 + 256]u8 = undefined;
                const eh: *u16 = @ptrCast(@alignCast(&err[0]));
                eh.* = core.c.htons(OP_ERR);
                err[2] = 1;
                err[3] = 0;
                const emsg = "File not found";
                @memcpy(err[4..][0..emsg.len], emsg);
                err[4 + emsg.len] = 0;
                _ = core.c.sendto(sock, &err, 4 + emsg.len + 1, 0,
                    .{ .__sockaddr_in__ = @ptrCast(&from) }, fromlen);
                continue;
            }
            defer _ = core.c.close(fd);

            var data: [4 + 512]u8 = undefined;
            const dh: *u16 = @ptrCast(@alignCast(&data[0]));
            dh.* = core.c.htons(OP_DATA);
            var block: u16 = 1;
            var tftp_fd: c_int = -1;

            const tftp_sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
            if (tftp_sock < 0) continue;

            while (true) {
                const rd = core.c.read(fd, &data[4], 512);
                if (rd < 0) break;
                const bh: *u16 = @ptrCast(@alignCast(&data[2]));
                bh.* = core.c.htons(block);
                const total = 4 + @as(usize, @intCast(rd));
                _ = core.c.sendto(tftp_sock, &data, total, 0,
                    .{ .__sockaddr_in__ = @ptrCast(&from) }, fromlen);

                if (rd < 512) break;

                var ack: [1024]u8 = undefined;
                var ack_from: core.c.struct_sockaddr_in = undefined;
                var ack_len: core.c.socklen_t = @sizeOf(@TypeOf(ack_from));
                var tv: core.c.struct_timeval = .{ .tv_sec = 2, .tv_usec = 0 };
                _ = core.c.setsockopt(tftp_sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));
                const an = core.c.recvfrom(tftp_sock, &ack, ack.len, 0,
                    .{ .__sockaddr_in__ = @ptrCast(&ack_from) }, &ack_len);
                if (an < 4) break;
                block += 1;
                tftp_fd = tftp_sock;
            }
        }
    }
}
