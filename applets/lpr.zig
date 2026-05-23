const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lpr", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: lpr FILE\n", .{});
    const alloc = std.heap.page_allocator;

    const file = args[1];
    const file_z = alloc.dupeZ(u8, file) catch return 1;
    defer alloc.free(file_z);

    var st: core.c.struct_stat = undefined;
    if (core.c.stat(file_z.ptr, &st) < 0) return core.die(1, "lpr: cannot open {s}\n", .{file});

    const fd = core.c.open(file_z.ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "lpr: cannot open {s}\n", .{file});
    defer _ = core.c.close(fd);

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return 1;
    defer _ = core.c.close(sock);

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.htonl(@as(u32, 0x7F000001));
    addr.sin_port = core.c.htons(515);

    if (core.c.connect(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "lpr: cannot connect to lpd\n", .{});

    const user = core.c.getlogin();
    const user_s = if (user) |u| std.mem.sliceTo(@as([*]u8, @ptrCast(u)), 0) else "unknown";

    var ctrl: [512]u8 = undefined;
    const ctrl_data = std.fmt.bufPrint(&ctrl, "2 {s} {s}\n", .{ user_s, file }) catch return 1;
    _ = core.c.write(sock, &ctrl, @as(usize, ctrl_data.len));

    var size_buf: [32]u8 = undefined;
    const size_str = std.fmt.bufPrint(&size_buf, "{d}", .{st.st_size}) catch return 1;
    _ = core.c.write(sock, size_str.ptr, size_str.len);

    var ack_storage: [1]u8 = undefined;
    _ = core.c.read(sock, &ack_storage, 1);

    while (true) {
        const data = core.readAll(alloc, fd, 4096) catch break;
        defer alloc.free(data);
        if (data.len == 0) break;
        _ = core.c.write(sock, data.ptr, data.len);
    }

    return 0;
}
