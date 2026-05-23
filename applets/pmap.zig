const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "pmap", .main = main };

const alloc = std.heap.page_allocator;

fn hexStr(buf: []u8, val: u64, width: usize) []const u8 {
    for (0..width) |i| {
        const shift = @as(u6, @intCast((width - 1 - i) * 4));
        const nib = @as(u8, @intCast((val >> shift) & 0xf));
        buf[i] = if (nib < 10) '0' + nib else 'a' + nib - 10;
    }
    return buf[0..width];
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: pmap [-x] [-d] [-q] PID\n", .{});

    var i: usize = 1;
    var opt_quiet = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) {
            i += 1;
            break;
        }
        for (args[i][1..]) |c| {
            switch (c) {
                'x', 'd' => {},
                'q' => opt_quiet = true,
                else => return core.die(1, "pmap: unknown option -{c}\n", .{c}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "pmap: no PID specified\n", .{});
    const pid = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "pmap: invalid PID '{s}'\n", .{args[i]});

    var path_buf: [128]u8 = undefined;
    const map_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/maps", .{pid}) catch return 1;
    var z_buf: [256:0]u8 = undefined;
    if (map_path.len >= z_buf.len) return 1;
    @memcpy(z_buf[0..map_path.len], map_path);
    z_buf[map_path.len] = 0;

    const fd = core.c.open(&z_buf, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "pmap: cannot open maps for PID {d}\n", .{pid});
    defer _ = core.c.close(fd);

    const data = core.readAll(alloc, fd, 262144) catch return 1;
    defer alloc.free(data);

    if (!opt_quiet) {
        core.writeAll(1, "Address           Kbytes     RSS   Dirty Mode  Mapping\n");
    }

    var total_kb: u64 = 0;

    var pos: usize = 0;
    while (pos < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[pos..], '\n') orelse data.len;
        const line = data[pos .. pos + nl];
        pos += nl + 1;
        if (line.len == 0) continue;

        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const addr_range = it.next() orelse continue;
        const perms = it.next() orelse continue;
        _ = it.next() orelse continue;
        _ = it.next() orelse continue;
        _ = it.next() orelse continue;

        const mapping = it.rest();

        const dash = std.mem.indexOfScalar(u8, addr_range, '-') orelse continue;
        const start_addr = std.fmt.parseUnsigned(u64, addr_range[0..dash], 16) catch continue;
        const end_addr = std.fmt.parseUnsigned(u64, addr_range[dash + 1 ..], 16) catch continue;
        const size = end_addr - start_addr;
        const kb = size / 1024;

        total_kb += kb;

        var out: [256]u8 = undefined;
        var hbuf: [12]u8 = undefined;
        _ = hexStr(&hbuf, start_addr, 12);
        const out_line = std.fmt.bufPrint(&out, "{s} {d:>8}  {s:>5}  {s}\n", .{
            hbuf[0..12], kb, perms, mapping,
        }) catch continue;
        core.writeAll(1, out_line);
    }

    if (!opt_quiet and total_kb > 0) {
        var footer: [128]u8 = undefined;
        const f_line = std.fmt.bufPrint(&footer, "total           {d:>8}\n", .{total_kb}) catch return 1;
        core.writeAll(1, f_line);
    }

    return 0;
}
