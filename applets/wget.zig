const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "wget", .main = main };

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: wget URL\n", .{});
    const alloc = std.heap.page_allocator;
    const url = args[1];

    if (!std.mem.startsWith(u8, url, "http://"))
        return core.die(1, "wget: only http:// supported\n", .{});

    const rest = url[7..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    const host_part = rest[0..slash];
    const path = if (slash < rest.len) rest[slash..] else "/";

    var host: []const u8 = host_part;
    var port: u16 = 80;
    if (std.mem.indexOfScalar(u8, host_part, ':')) |colon| {
        host = host_part[0..colon];
        port = std.fmt.parseInt(u16, host_part[colon + 1 ..], 10) catch
            return core.die(1, "wget: invalid port\n", .{});
    }

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);

    const he = core.c.gethostbyname(host_z.ptr) orelse
        return core.die(1, "wget: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "wget: connection failed\n", .{});

    var req: [4096]u8 = undefined;
    const req_sl = (std.fmt.bufPrint(&req,
        "GET {s} HTTP/1.0\r\nHost: {s}\r\nConnection: close\r\n\r\n",
        .{ path, host },
    ) catch req[0..0]);
    if (req_sl.len == 0) return 1;
    _ = core.c.send(sock, req_sl.ptr, req_sl.len, 0);

    var resp: [65536]u8 = undefined;
    const total = core.c.recv(sock, &resp, resp.len, 0);
    if (total <= 0) return core.die(1, "wget: no response\n", .{});

    const resp_slice = resp[0..@as(usize, @intCast(total))];
    const sep = std.mem.indexOf(u8, resp_slice, "\r\n\r\n") orelse
        return core.die(1, "wget: invalid response\n", .{});
    const body = resp_slice[sep + 4 ..];

    const fname = if (std.mem.lastIndexOfScalar(u8, path, '/')) |ls|
        if (ls + 1 < path.len) path[ls + 1 ..] else "index.html"
    else "index.html";
    const filename = if (fname.len == 0) "index.html" else fname;

    const fname_z = alloc.dupeZ(u8, filename) catch return 1;
    defer alloc.free(fname_z);

    const outfd = core.c.open(fname_z.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (outfd < 0) return core.die(1, "wget: cannot write {s}\n", .{filename});
    defer _ = core.c.close(outfd);

    core.writeAll(outfd, body);

    var msg: [256]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "wget: saved {d} bytes to {s}\n", .{ body.len, filename }) catch return 0;
    core.writeAll(1, m);
    return 0;
}
