const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "telnetd", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var port: u16 = 23;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch 23;
        }
    }

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "telnetd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "telnetd: bind (need root)\n", .{});
    if (core.c.listen(sock, 5) < 0)
        return core.die(1, "telnetd: listen\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "telnetd: listening on port {d}\n", .{port}) catch "telnetd: started\n";
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
            _ = core.c.dup2(client, 2);
            for (3..64) |nfd| _ = core.c.close(@intCast(nfd));

            const negotiate = "\xFF\xFD\x18\xFF\xFD\x20\xFF\xFD\x23\xFF\xFD\x27";
            _ = core.c.write(1, negotiate, 12);

            const login_path = "/bin/login";
            const login_z = alloc.dupeZ(u8, login_path) catch core.c._exit(1);
            var argv: [2][*:0]u8 = undefined;
            argv[0] = @ptrCast(login_z.ptr);
            argv[1] = undefined;
            _ = core.c.execve(login_z.ptr, &argv, null);

            const shell = "/bin/sh";
            const shell_z = alloc.dupeZ(u8, shell) catch core.c._exit(1);
            var argv2: [2][*:0]u8 = undefined;
            argv2[0] = @ptrCast(shell_z.ptr);
            argv2[1] = undefined;
            _ = core.c.execve(shell_z.ptr, &argv2, null);
            core.c._exit(1);
        }
        _ = core.c.close(client);
    }
}
