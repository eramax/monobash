const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "udpsvd", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: udpsvd IP PORT PROG [ARGS...]\n", .{});

    const alloc = std.heap.page_allocator;
    var i: usize = 1;

    while (i < args.len and args[i][0] == '-') : (i += 1) {}

    if (i + 2 >= args.len) return core.die(1, "udpsvd: missing arguments\n", .{});
    const bind_ip = args[i];
    const port_str = args[i + 1];
    const prog = args[i + 2];
    const prog_args = if (i + 3 < args.len) args[i + 3..] else args[i + 2 ..];

    const port = std.fmt.parseInt(u16, port_str, 10) catch return core.die(1, "udpsvd: bad port\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "udpsvd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = if (bind_ip.len == 0 or std.mem.eql(u8, bind_ip, "0") or std.mem.eql(u8, bind_ip, "*"))
        core.c.INADDR_ANY
    else
        core.c.inet_addr(@as([*]const u8, @ptrCast(bind_ip.ptr)));
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "udpsvd: bind\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "udpsvd: listening on port {d}\n", .{port}) catch "udpsvd: started\n";
    core.writeAll(1, m);

    while (true) {
        var buf: [65536]u8 = undefined;
        var from: core.c.struct_sockaddr_in = undefined;
        var fromlen: core.c.socklen_t = @sizeOf(@TypeOf(from));
        const n = core.c.recvfrom(sock, &buf, buf.len, 0,
            .{ .__sockaddr_in__ = @ptrCast(&from) }, &fromlen);
        if (n < 0) continue;

        const pid = core.c.fork();
        if (pid == 0) {
            const psock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
            if (psock >= 0) {
                _ = core.c.connect(psock, .{ .__sockaddr_in__ = @ptrCast(&from) }, fromlen);
                _ = core.c.dup2(psock, 0);
                _ = core.c.dup2(psock, 1);
                for (3..64) |nfd| _ = core.c.close(@intCast(nfd));
                _ = core.c.write(1, &buf, @as(usize, @intCast(n)));
            }

            const prog_z = alloc.dupeZ(u8, prog) catch core.c._exit(1);
            var argv: [4][*:0]u8 = undefined;
            argv[0] = @ptrCast(prog_z.ptr);
            for (0..prog_args.len) |j| {
                if (j + 1 < argv.len) argv[j + 1] = @ptrCast(@constCast(prog_args[j].ptr));
            }
            _ = core.c.execve(prog_z.ptr, &argv, null);
            core.c._exit(1);
        }
    }
}
