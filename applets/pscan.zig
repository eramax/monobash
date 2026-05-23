const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "pscan", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: pscan [-p MIN] [-P MAX] [-t TIMEOUT] HOST\n", .{});
    const alloc = std.heap.page_allocator;

    var i: usize = 1;
    var min_port: u16 = 1;
    var max_port: u16 = 1024;
    var timeout_ms: u64 = 5000;
    var host: []const u8 = "";

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") and i + 1 < args.len) { i += 1; min_port = std.fmt.parseInt(u16, args[i], 10) catch 1; }
        else if (std.mem.eql(u8, arg, "-P") and i + 1 < args.len) { i += 1; max_port = std.fmt.parseInt(u16, args[i], 10) catch 1024; }
        else if (std.mem.eql(u8, arg, "-t") and i + 1 < args.len) { i += 1; timeout_ms = std.fmt.parseInt(u64, args[i], 10) catch 5000; }
        else if (host.len == 0) host = arg;
    }
    if (host.len == 0) return core.die(1, "pscan: missing host\n", .{});

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "pscan: unknown host\n", .{});

    var addr_bytes: [4]u8 = undefined;
    const ap = he.*.h_addr_list[0] orelse return 1;
    @memcpy(&addr_bytes, ap[0..4]);
    const addr_hex = @as(u32, @bitCast(addr_bytes));

    var out: [128]u8 = undefined;
    const o = std.fmt.bufPrint(&out, "Scanning {s} ports {d} to {d}\nPort\tState\n", .{ host, min_port, max_port }) catch "pscan\n";
    core.writeAll(1, o);

    var port = min_port;
    while (port <= max_port) : (port += 1) {
        const s = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
        if (s < 0) continue;

        const flags = core.c.fcntl(s, core.c.F_GETFL, @as(c_int, 0));
        _ = core.c.fcntl(s, core.c.F_SETFL, flags | core.c.O_NONBLOCK);

        var dst: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
        dst.sin_family = core.c.AF_INET;
        dst.sin_addr.s_addr = addr_hex;
        dst.sin_port = core.c.htons(port);

        const rc = core.c.connect(s, .{ .__sockaddr_in__ = @ptrCast(&dst) }, @sizeOf(@TypeOf(dst)));

        if (rc == 0) {
            var pbuf: [64]u8 = undefined;
            const ps = std.fmt.bufPrint(&pbuf, "{d}\topen\n", .{port}) catch continue;
            core.writeAll(1, ps);
        } else {
            var poll_fds: [1]core.c.struct_pollfd = undefined;
            poll_fds[0].fd = s;
            poll_fds[0].events = core.c.POLLOUT;
            const prc = core.c.poll(&poll_fds, 1, @intCast(timeout_ms));
            if (prc > 0 and (poll_fds[0].revents & core.c.POLLOUT) != 0) {
                var so_error: c_int = 0;
                var optlen: core.c.socklen_t = @sizeOf(c_int);
                if (core.c.getsockopt(s, core.c.SOL_SOCKET, core.c.SO_ERROR, &so_error, &optlen) == 0 and so_error == 0) {
                    var pbuf: [64]u8 = undefined;
                    const ps = std.fmt.bufPrint(&pbuf, "{d}\topen\n", .{port}) catch continue;
                    core.writeAll(1, ps);
                }
            }
        }
        _ = core.c.close(s);
    }

    return 0;
}
