const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "inetd", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var conf_file: []const u8 = "/etc/inetd.conf";

    if (args.len > 1) conf_file = args[1];

    const cf_z = alloc.dupeZ(u8, conf_file) catch return 1;
    defer alloc.free(cf_z);
    const cf = core.c.open(cf_z.ptr, core.c.O_RDONLY);
    if (cf < 0) return core.die(1, "inetd: cannot open {s}\n", .{conf_file});

    const data = core.readAll(alloc, cf, 65536) catch return 1;
    defer _ = core.c.close(cf);
    defer alloc.free(data);

    core.writeAll(1, "inetd: started\n");

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var fields = std.mem.splitScalar(u8, trimmed, ' ');
        var f: [7][]const u8 = undefined;
        var fc: usize = 0;
        while (fields.next()) |field| {
            if (field.len > 0 and fc < 7) { f[fc] = field; fc += 1; }
        }
        if (fc < 6) continue;

        _ = f[0]; _ = f[1]; _ = f[2]; _ = f[3]; _ = f[4];
        const program = f[5];

        const port = f[0];

        const prog_z = alloc.dupeZ(u8, program) catch continue;
        const port_z = alloc.dupeZ(u8, port) catch continue;

        const he = core.c.getservbyname(port_z.ptr, null);
        var port_num: u16 = 0;
        if (he) |h| {
            port_num = core.c.ntohs(@as(u16, @intCast(h.*.s_port)));
        } else {
            port_num = std.fmt.parseInt(u16, port, 10) catch continue;
        }

        _ = core.c.fork();
        var sin: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
        sin.sin_family = core.c.AF_INET;
        sin.sin_addr.s_addr = core.c.INADDR_ANY;
        sin.sin_port = core.c.htons(port_num);

        const s = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
        if (s < 0) continue;

        var opt: c_int = 1;
        _ = core.c.setsockopt(s, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

        if (core.c.bind(s, .{ .__sockaddr_in__ = @ptrCast(&sin) }, @sizeOf(@TypeOf(sin))) < 0) {
            _ = core.c.close(s);
            continue;
        }
        _ = core.c.listen(s, 10);

        var msg: [128]u8 = undefined;
        const m = std.fmt.bufPrint(&msg, "inetd: {s} on port {d}\n", .{ program, port_num }) catch continue;
        core.writeAll(1, m);

        while (true) {
            var cli: core.c.struct_sockaddr_in = undefined;
            var clen: core.c.socklen_t = @sizeOf(@TypeOf(cli));
            const client = core.c.accept(s, .{ .__sockaddr_in__ = @ptrCast(&cli) }, &clen);
            if (client < 0) continue;

            const pid = core.c.fork();
            if (pid == 0) {
                _ = core.c.dup2(client, 0);
                _ = core.c.dup2(client, 1);
                _ = core.c.dup2(client, 2);
                for (3..64) |nfd| _ = core.c.close(@intCast(nfd));

                var argv: [2][*:0]u8 = undefined;
                argv[0] = @ptrCast(prog_z.ptr);
                argv[1] = undefined;
                _ = core.c.execve(prog_z.ptr, &argv, null);
                core.c._exit(1);
            }
            _ = core.c.close(client);
        }
    }

    return 0;
}
