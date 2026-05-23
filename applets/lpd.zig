const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lpd", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "lpd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(515);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "lpd: bind (need root)\n", .{});
    if (core.c.listen(sock, 5) < 0)
        return core.die(1, "lpd: listen\n", .{});

    core.writeAll(1, "lpd: listening on port 515\n");

    while (true) {
        var cli: core.c.struct_sockaddr_in = undefined;
        var clen: core.c.socklen_t = @sizeOf(@TypeOf(cli));
        const client = core.c.accept(sock, .{ .__sockaddr_in__ = @ptrCast(&cli) }, &clen);
        if (client < 0) continue;

        var buf: [1024]u8 = undefined;
        const n = core.c.read(client, &buf, buf.len);
        if (n > 0) {
            cmd: {
                const cmd_byte = buf[0];
                const rest = std.mem.trim(u8, buf[1..@as(usize, @intCast(n))], "\r\n");
                if (rest.len == 0) break :cmd;

                if (cmd_byte == 2) {
                    const sp = std.mem.indexOfScalar(u8, rest, ' ') orelse break :cmd;
                    const queue = rest[0..sp];
                    _ = queue;
                    const sp2 = std.mem.indexOfScalar(u8, rest[sp + 1 ..], ' ') orelse break :cmd;
                    const user = rest[sp + 1 .. sp + 1 + sp2];
                    const name = rest[sp + 1 + sp2 + 1 ..];
                    _ = user; _ = name;

                    var sub_buf: [1024]u8 = undefined;
                    const sub_n = core.c.read(client, &sub_buf, sub_buf.len);
                    if (sub_n > 0 and sub_buf[0] == 3) {
                        var ctrl_size: u32 = 0;
                        for (1..@as(usize, @intCast(sub_n))) |j| {
                            const c = sub_buf[j];
                            if (c >= '0' and c <= '9') {
                                ctrl_size = ctrl_size * 10 + (c - '0');
                            } else break;
                        }

                        const ctrl_data = alloc.alloc(u8, ctrl_size) catch break :cmd;
                        defer alloc.free(ctrl_data);
                        var cpos: usize = 0;
                        while (cpos < ctrl_size) {
                            const r = core.c.read(client, ctrl_data.ptr + cpos, ctrl_size - cpos);
                            if (r <= 0) break;
                            cpos += @as(usize, @intCast(r));
                        }

                        const ack = [1]u8{0};
                        _ = core.c.write(client, &ack, 1);

                        var df: [1024]u8 = undefined;
                        const df_n = core.c.read(client, &df, df.len);
                        if (df_n > 0 and df[0] == 3) {
                            var df_size: u32 = 0;
                            for (1..@as(usize, @intCast(df_n))) |j| {
                                const c = df[j];
                                if (c >= '0' and c <= '9') {
                                    df_size = df_size * 10 + (c - '0');
                                } else break;
                            }
                            const df_data = alloc.alloc(u8, df_size) catch break :cmd;
                            defer alloc.free(df_data);
                            var dpos: usize = 0;
                            while (dpos < df_size) {
                                const r = core.c.read(client, df_data.ptr + dpos, df_size - dpos);
                                if (r <= 0) break;
                                dpos += @as(usize, @intCast(r));
                            }
                        }
                    }
                }
            }
        }
        _ = core.c.close(client);
    }
}
