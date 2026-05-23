const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "nbd-client", .main = main };

const NBD_SET_SOCK: c_ulong = 0xab00;
const NBD_SET_BLKSIZE: c_ulong = 0xab01;
const NBD_SET_SIZE: c_ulong = 0xab02;
const NBD_DO_IT: c_ulong = 0xab03;
const NBD_CLEAR_SOCK: c_ulong = 0xab04;
const NBD_DISCONNECT: c_ulong = 0xab08;

fn netU32(bytes: [*c]u8) u32 {
    var buf: [4]u8 = undefined;
    @memcpy(buf[0..], bytes[0..4]);
    return @as(u32, @bitCast(buf));
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: nbd-client HOST [PORT] BLOCKDEV\n", .{});

    const alloc = std.heap.page_allocator;
    _ = &args;
    var host: []const u8 = "";
    var port: u16 = 10809;
    var device: []const u8 = "";

    if (std.mem.eql(u8, args[1], "-d")) {
        device = args[2];
        const dev_z = alloc.dupeZ(u8, device) catch return 1;
        defer alloc.free(dev_z);
        const dev_fd = core.c.open(dev_z.ptr, core.c.O_RDWR);
        if (dev_fd >= 0) {
            _ = core.c.ioctl(dev_fd, NBD_CLEAR_SOCK, @as(c_ulong, 0));
            _ = core.c.ioctl(dev_fd, NBD_DISCONNECT, @as(c_ulong, 0));
            _ = core.c.close(dev_fd);
        }
        return 0;
    }

    host = args[1];
    if (args.len >= 4) {
        port = std.fmt.parseInt(u16, args[2], 10) catch 10809;
        device = args[3];
    } else {
        device = args[2];
    }

    const host_z = alloc.dupeZ(u8, host) catch return 1;
    defer alloc.free(host_z);
    const he = core.c.gethostbyname(host_z.ptr) orelse return core.die(1, "nbd-client: unknown host\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    const ap = he.*.h_addr_list[0] orelse return 1;
    addr.sin_addr.s_addr = netU32(ap);
    addr.sin_port = core.c.htons(port);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "nbd-client: connection failed\n", .{});

    var magic: [8]u8 = undefined;
    const mr = core.c.read(sock, &magic, 8);
    if (mr < 8) return core.die(1, "nbd-client: handshake failed\n", .{});

    var old_hdr: struct { devsize: u64, flags: u32, data: [124]u8 } = undefined;
    const hr = core.c.read(sock, @as([*]u8, @ptrCast(&old_hdr)), @sizeOf(@TypeOf(old_hdr)));
    if (hr < @sizeOf(@TypeOf(old_hdr))) return core.die(1, "nbd-client: handshake failed\n", .{});

    const devsize: u64 = 0;
    const dev_z = alloc.dupeZ(u8, device) catch return 1;
    defer alloc.free(dev_z);
    const dev_fd = core.c.open(dev_z.ptr, core.c.O_RDWR);
    if (dev_fd < 0) return core.die(1, "nbd-client: cannot open {s}\n", .{device});

    _ = core.c.ioctl(dev_fd, NBD_SET_SOCK, @as(c_uint, @bitCast(@as(c_int, sock))));
    _ = core.c.ioctl(dev_fd, NBD_SET_BLKSIZE, @as(c_uint, 4096));
    _ = core.c.ioctl(dev_fd, NBD_SET_SIZE, @as(c_uint, @intCast(devsize)));
    _ = core.c.ioctl(dev_fd, NBD_DO_IT, @as(c_ulong, 0));
    _ = core.c.ioctl(dev_fd, NBD_CLEAR_SOCK, @as(c_ulong, 0));

    _ = core.c.close(dev_fd);
    _ = core.c.close(sock);
    return 0;
}
