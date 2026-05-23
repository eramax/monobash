const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tftp", .main = main };

const TFTP_PORT = 69;
const OP_RRQ: u16 = 1;
const OP_DATA: u16 = 3;
const OP_ACK: u16 = 4;
const OP_ERROR: u16 = 5;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: tftp HOST [FILE]\n", .{});
    const alloc = std.heap.page_allocator;
    const host = args[1];
    const filename = if (args.len > 2) args[2] else "test.txt";

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "tftp: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "tftp: socket\n", .{});

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 5;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    var addr_bytes: [4]u8 = undefined;
    @memcpy(&addr_bytes, ap[0..4]);
    addr.sin_addr.s_addr = @as(u32, @bitCast(addr_bytes));
    addr.sin_port = core.c.htons(TFTP_PORT);

    var rrq: [512]u8 = undefined;
    var rrq_len: usize = 0;
    rrq[0] = 0;
    rrq[1] = OP_RRQ;
    rrq_len = 2;
    @memcpy(rrq[rrq_len..], filename);
    rrq_len += filename.len;
    rrq[rrq_len] = 0;
    rrq_len += 1;
    @memcpy(rrq[rrq_len..], "octet");
    rrq_len += 5;
    rrq[rrq_len] = 0;
    rrq_len += 1;

    const n = core.c.sendto(sock, &rrq, rrq_len, 0,
        .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr)));
    if (n < 0) return core.die(1, "tftp: send failed\n", .{});

    const out_name = alloc.dupeZ(u8, filename) catch return 1;
    defer alloc.free(out_name);
    const outfd = core.c.open(out_name.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (outfd < 0) return core.die(1, "tftp: cannot write '{s}'\n", .{filename});

    var block: u16 = 0;
    var server_addr: core.c.struct_sockaddr_in = undefined;
    var server_len: core.c.socklen_t = @sizeOf(@TypeOf(server_addr));
    var total: usize = 0;

    while (true) {
        var pkt: [516]u8 = undefined;
        const rn = core.c.recvfrom(sock, &pkt, pkt.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&server_addr) }, &server_len);
        if (rn < 4) {
            core.writeAll(1, "tftp: timeout or error\n");
            break;
        }

        const op = (@as(u16, pkt[0]) << 8) | pkt[1];
        if (op == OP_ERROR) {
            const err_msg = pkt[4..@as(usize, @intCast(rn))];
            var eb: [128]u8 = undefined;
            const e = std.fmt.bufPrint(&eb, "tftp: error: {s}\n", .{std.mem.sliceTo(err_msg, 0)}) catch "tftp: error\n";
            core.writeAll(1, e);
            break;
        }
        if (op != OP_DATA) {
            core.writeAll(1, "tftp: unexpected packet\n");
            break;
        }

        const blk = (@as(u16, pkt[2]) << 8) | pkt[3];
        if (blk != block + 1) {
            break;
        }
        block = blk;

        const data_len = @as(usize, @intCast(rn)) - 4;
        if (data_len > 0) {
            core.writeAll(outfd, pkt[4..][0..data_len]);
            total += data_len;
        }

        var ack: [4]u8 = undefined;
        ack[0] = 0;
        ack[1] = OP_ACK;
        ack[2] = @as(u8, @intCast(block >> 8));
        ack[3] = @as(u8, @intCast(block & 0xFF));
        _ = core.c.sendto(sock, &ack, 4, 0,
            .{ .__sockaddr_in__ = @ptrCast(&server_addr) }, @sizeOf(@TypeOf(server_addr)));

        if (data_len < 512) break;
    }

    _ = core.c.close(outfd);
    _ = core.c.close(sock);

    var msg: [256]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "tftp: received {d} bytes to {s}\n", .{ total, filename }) catch "tftp: done\n";
    core.writeAll(1, m);
    return 0;
}
