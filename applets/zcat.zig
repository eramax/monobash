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
    const buf = core.readAll(std.heap.page_allocator, fd, 4) catch return null;
    defer std.heap.page_allocator.free(buf);
    if (buf.len < 4) return null;
    return @as(u32, buf[0]) | (@as(u32, buf[1]) << 8) | (@as(u32, buf[2]) << 16) | (@as(u32, buf[3]) << 24);
}

fn readAllFd(alloc: std.mem.Allocator, fd: c_int) ![]u8 {
    return core.readAll(alloc, fd, 1 << 28);
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
    const hdr_data = core.readAll(std.heap.page_allocator, in_fd, 10) catch return 1;
    defer std.heap.page_allocator.free(hdr_data);
    if (hdr_data.len < 10) return 1;
    const hdr = hdr_data[0..10];

    if (hdr[0] != 0x1F or hdr[1] != 0x8B) return core.die(1, "zcat: not in gzip format\n", .{});
    if (hdr[2] != 0) return core.die(1, "zcat: unsupported compression method\n", .{});

    const flg = hdr[3];
    if (flg & 0x04 != 0) {
        const xlen_data = core.readAll(std.heap.page_allocator, in_fd, 2) catch return 1;
        defer std.heap.page_allocator.free(xlen_data);
        if (xlen_data.len < 2) return 1;
        var xlen: usize = @as(usize, xlen_data[0]) | (@as(usize, xlen_data[1]) << 8);
        while (xlen > 0) {
            const r = @min(xlen, 256);
            const tmp = core.readAll(std.heap.page_allocator, in_fd, r) catch return 1;
            defer std.heap.page_allocator.free(tmp);
            if (tmp.len == 0) return 1;
            xlen -|= tmp.len;
        }
    }
    if (flg & 0x08 != 0) {
        while (true) {
            const b_data = core.readAll(std.heap.page_allocator, in_fd, 1) catch return 1;
            defer std.heap.page_allocator.free(b_data);
            if (b_data.len == 0) return 1;
            if (b_data[0] == 0) break;
        }
    }
    if (flg & 0x10 != 0) {
        while (true) {
            const b_data = core.readAll(std.heap.page_allocator, in_fd, 1) catch return 1;
            defer std.heap.page_allocator.free(b_data);
            if (b_data.len == 0) return 1;
            if (b_data[0] == 0) break;
        }
    }
    if (flg & 0x02 != 0) {
        const chk_data = core.readAll(std.heap.page_allocator, in_fd, 2) catch return 1;
        defer std.heap.page_allocator.free(chk_data);
        if (chk_data.len < 2) return 1;
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

    core.writeAll(out_fd, data[0..data.len - 8]);
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
