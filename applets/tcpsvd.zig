const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tcpsvd", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: tcpsvd [-h] IP PORT PROG [ARGS...]\n", .{});

    const alloc = std.heap.page_allocator;
    var i: usize = 1;
    var opt_h = false;

    while (i < args.len and args[i][0] == '-') : (i += 1) {
        if (std.mem.eql(u8, args[i], "-h")) opt_h = true;
    }

    if (i + 2 >= args.len) return core.die(1, "tcpsvd: missing arguments\n", .{});
    const bind_ip = args[i];
    const port_str = args[i + 1];
    const prog = args[i + 2];
    const prog_args = if (i + 3 < args.len) args[i + 3..] else args[i + 2 ..];

    const port = std.fmt.parseInt(u16, port_str, 10) catch return core.die(1, "tcpsvd: bad port\n", .{});

    const bind_ip_z = alloc.dupeZ(u8, bind_ip) catch return 1;
    defer alloc.free(bind_ip_z);

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "tcpsvd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = if (bind_ip.len == 0 or std.mem.eql(u8, bind_ip, "0") or std.mem.eql(u8, bind_ip, "*"))
        core.c.INADDR_ANY
    else
        core.c.inet_addr(bind_ip_z.ptr);
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "tcpsvd: bind\n", .{});
    if (core.c.listen(sock, 5) < 0)
        return core.die(1, "tcpsvd: listen\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "tcpsvd: listening on port {d}\n", .{port}) catch "tcpsvd: started\n";
    core.writeAll(1, m);

    while (true) {
        var cli: core.c.struct_sockaddr_in = undefined;
        var clen: core.c.socklen_t = @sizeOf(@TypeOf(cli));
        const client = core.c.accept(sock, .{ .__sockaddr_in__ = @ptrCast(&cli) }, &clen);
        if (client < 0) continue;

        const pid = core.c.fork();
        if (pid == 0) {
            _ = core.c.close(sock);
            _ = core.c.dup2(client, 0);
            _ = core.c.dup2(client, 1);
            if (opt_h) _ = core.c.dup2(client, 2);
            for (3..64) |nfd| _ = core.c.close(@intCast(nfd));

            const prog_z = alloc.dupeZ(u8, prog) catch core.c._exit(1);
            var argv: [4][*:0]u8 = undefined;
            argv[0] = @ptrCast(prog_z.ptr);
            for (0..prog_args.len) |j| {
                if (j + 1 < argv.len) argv[j + 1] = @ptrCast(@constCast(prog_args[j].ptr));
            }
            _ = core.c.execve(prog_z.ptr, &argv, null);
            core.c._exit(1);
        }
        _ = core.c.close(client);
    }
}
