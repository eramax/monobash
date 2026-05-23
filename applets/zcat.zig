const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "zcat", .main = main };

fn crc32(data: []const u8) u32 {
    var table: [256]u32 = undefined;
    for (&table, 0..) |*c, i| {
        var crc: u32 = @intCast(i);
        for (0..8) |_| crc = if (crc & 1 != 0) (crc >> 1) ^ 0xEDB88320 else crc >> 1;
        c.* = crc;
    }
    var crc: u32 = 0xFFFFFFFF;
    for (data) |b| crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFF;
}

fn readLe32(fd: c_int) ?u32 {
    var buf: [4]u8 = undefined;
    var off: usize = 0;
    while (off < 4) {
        const n = core.c.read(fd, @as([*]u8, @ptrCast(&buf)) + off, 4 - off);
        if (n <= 0) return null;
        off += @intCast(n);
    }
    return @as(u32, buf[0]) | (@as(u32, buf[1]) << 8) | (@as(u32, buf[2]) << 16) | (@as(u32, buf[3]) << 24);
}

fn readAllFd(alloc: std.mem.Allocator, fd: c_int) ![]u8 {
    var buf = try alloc.alloc(u8, 65536);
    var pos: usize = 0;
    while (true) {
        if (pos >= buf.len) buf = try alloc.realloc(buf, buf.len * 2);
        const n = core.c.read(fd, buf.ptr + pos, buf.len - pos);
        if (n < 0) return error.ReadError;
        if (n == 0) break;
        pos += @intCast(n);
    }
    return buf[0..pos];
}

fn decompressToStdout(file: []const u8) u8 {
    var in_buf: [4096:0]u8 = undefined;
    if (file.len >= in_buf.len) return 1;
    @memcpy(in_buf[0..file.len], file);
    in_buf[file.len] = 0;

    const in_fd = core.c.open(in_buf[0..file.len :0].ptr, core.c.O_RDONLY);
    if (in_fd < 0) return core.die(1, "zcat: cannot open '{s}'\n", .{file});
    defer _ = core.c.close(in_fd);

    return decompressFd(in_fd, 1);
}

fn decompressFd(in_fd: c_int, out_fd: c_int) u8 {
    var hdr: [10]u8 = undefined;
    var off: usize = 0;
    while (off < 10) {
        const n = core.c.read(in_fd, @as([*]u8, @ptrCast(&hdr)) + off, 10 - off);
        if (n <= 0) return 1;
        off += @intCast(n);
    }

    if (hdr[0] != 0x1F or hdr[1] != 0x8B) return core.die(1, "zcat: not in gzip format\n", .{});
    if (hdr[2] != 0) return core.die(1, "zcat: unsupported compression method\n", .{});

    const flg = hdr[3];
    if (flg & 0x04 != 0) {
        var xlen_buf: [2]u8 = undefined;
        off = 0;
        while (off < 2) {
            const n = core.c.read(in_fd, @as([*]u8, @ptrCast(&xlen_buf)) + off, 2 - off);
            if (n <= 0) return 1;
            off += @intCast(n);
        }
        var xlen: usize = @as(usize, xlen_buf[0]) | (@as(usize, xlen_buf[1]) << 8);
        while (xlen > 0) {
            var tmp: [256]u8 = undefined;
            const r = @min(xlen, tmp.len);
            const n = core.c.read(in_fd, &tmp, r);
            if (n <= 0) return 1;
            xlen -|= @as(usize, @intCast(n));
        }
    }
    if (flg & 0x08 != 0) {
        while (true) {
            var b: u8 = 0;
            if (core.c.read(in_fd, &b, 1) <= 0) return 1;
            if (b == 0) break;
        }
    }
    if (flg & 0x10 != 0) {
        while (true) {
            var b: u8 = 0;
            if (core.c.read(in_fd, &b, 1) <= 0) return 1;
            if (b == 0) break;
        }
    }
    if (flg & 0x02 != 0) {
        var chk: [2]u8 = undefined;
        off = 0;
        while (off < 2) {
            const n = core.c.read(in_fd, @as([*]u8, @ptrCast(&chk)) + off, 2 - off);
            if (n <= 0) return 1;
            off += @intCast(n);
        }
    }

    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, in_fd) catch return 1;
    defer alloc.free(data);
    if (data.len < 8) return 1;

    const stored_crc = readLe32(in_fd) orelse return 1;
    const stored_size = readLe32(in_fd) orelse return 1;

    const actual_crc = crc32(data[0..data.len - 8]);
    const actual_size = @as(u32, @intCast((data.len - 8) & 0xFFFFFFFF));

    if (stored_crc != actual_crc) return core.die(1, "zcat: crc error\n", .{});
    if (stored_size != actual_size) return core.die(1, "zcat: size error\n", .{});

    var pos: usize = 0;
    while (pos < data.len - 8) {
        const w = core.c.write(out_fd, data.ptr + pos, (data.len - 8) - pos);
        if (w < 0) return 1;
        pos += @intCast(w);
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) {
        return decompressFd(0, 1);
    }

    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                else => return core.die(1, "zcat: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    var rc: u8 = 0;
    while (i < args.len) {
        const file = args[i];
        i += 1;
        rc |= decompressToStdout(file);
    }
    return rc;
}
