const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ntpd", .main = main };

const NTP_PORT = 123;
const NTP_PACKET_SIZE = 48;
const NTP_TIMESTAMP_DELTA: u64 = 2208988800;

fn ntpTimestampToUnix(ntp_ts: u64) u64 {
    const seconds = ntp_ts >> 32;
    return seconds - NTP_TIMESTAMP_DELTA;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var pool: []const u8 = "pool.ntp.org";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            i += 1;
            pool = args[i];
        } else return core.die(1, "usage: ntpd -p POOL\n", .{});
    }

    const pool_z = alloc.dupeZ(u8, pool) catch return 1;
    defer alloc.free(pool_z);

    const he = core.c.gethostbyname(pool_z.ptr) orelse
        return core.die(1, "ntpd: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "ntpd: socket\n", .{});

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = 5;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    var addr_bytes: [4]u8 = undefined;
    @memcpy(&addr_bytes, ap[0..4]);
    addr.sin_addr.s_addr = @as(u32, @bitCast(addr_bytes));
    addr.sin_port = core.c.htons(NTP_PORT);

    var pkt: [NTP_PACKET_SIZE]u8 = undefined;
    @memset(&pkt, 0);
    pkt[0] = 0x1B;

    const n = core.c.sendto(sock, &pkt, pkt.len, 0,
        .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr)));
    if (n < 0) return core.die(1, "ntpd: sendto failed\n", .{});

    var buf: [NTP_PACKET_SIZE]u8 = undefined;
    var from: core.c.struct_sockaddr_in = undefined;
    var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
    const rn = core.c.recvfrom(sock, &buf, buf.len, 0,
        .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
    if (rn < 0) return core.die(1, "ntpd: no response\n", .{});

    var ts_buf: [8]u8 = undefined;
    @memcpy(ts_buf[0..], buf[40..48]);

    var ntp_ts: u64 = 0;
    for (ts_buf) |b| ntp_ts = (ntp_ts << 8) | @as(u64, b);
    const unix_secs = ntpTimestampToUnix(ntp_ts);

    var now: core.c.struct_timeval = undefined;
    now.tv_sec = @as(c_long, @intCast(unix_secs));
    now.tv_usec = 0;

    const rc = core.c.settimeofday(&now, null);
    if (rc < 0) return core.die(1, "ntpd: settimeofday (need root)\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "ntpd: time set to {d}\n", .{unix_secs}) catch "ntpd: time set\n";
    core.writeAll(1, m);
    return 0;
}
