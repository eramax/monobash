const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cksum", .main = main };

fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc ^= byte;
        var i: u5 = 0;
        while (i < 8) : (i += 1) {
            if (crc & 1 == 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const files = args[1..];
    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1;
        defer alloc.free(data);
        const crc = crc32(data);
        var buf: [128]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d} {d}\n", .{ crc, data.len }) catch "";
        core.writeAll(1, s);
        return 0;
    }
    var exit: u8 = 0;
    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) { exit = 1; continue; }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) { core.eprint("cksum: {s}: No such file\n", .{f}); exit = 1; continue; }
        defer _ = core.c.close(fd);
        const data = core.readAll(alloc, fd, 1024 * 1024 * 16) catch { exit = 1; continue; };
        defer alloc.free(data);
        const crc = crc32(data);
        var buf: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d} {d} {s}\n", .{ crc, data.len, f }) catch "";
        core.writeAll(1, s);
    }
    return exit;
}
