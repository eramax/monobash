const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "gzip", .main = main };

fn crc32(data: []const u8) u32 {
    var table: [256]u32 = undefined;
    for (&table, 0..) |*c, i| {
        var crc: u32 = @intCast(i);
        for (0..8) |_| {
            crc = if (crc & 1 != 0) (crc >> 1) ^ 0xEDB88320 else crc >> 1;
        }
        c.* = crc;
    }
    var crc: u32 = 0xFFFFFFFF;
    for (data) |b| {
        crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
}

fn writeLe32(fd: c_int, val: u32) u8 {
    var buf: [4]u8 = undefined;
    buf[0] = @intCast(val & 0xFF);
    buf[1] = @intCast((val >> 8) & 0xFF);
    buf[2] = @intCast((val >> 16) & 0xFF);
    buf[3] = @intCast((val >> 24) & 0xFF);
    var off: usize = 0;
    while (off < 4) {
        const w = core.c.write(fd, @as([*]u8, @ptrCast(&buf)) + off, 4 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
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

fn doCompress(in_fd: c_int, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, in_fd) catch return 1;
    defer alloc.free(data);

    // Gzip header: magic, method=0 (stored), flags=0, mtime=0, xflags=0, os=255
    var hdr: [10]u8 = .{ 0x1F, 0x8B, 0, 0, 0, 0, 0, 0, 0, 255 };
    var off: usize = 0;
    while (off < 10) {
        const w = core.c.write(out_fd, @as([*]u8, @ptrCast(&hdr)) + off, 10 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }

    // Raw uncompressed data
    off = 0;
    while (off < data.len) {
        const w = core.c.write(out_fd, data.ptr + off, data.len - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }

    // CRC32 and original size
    const crc = crc32(data);
    const isz = @as(u32, @intCast(data.len & 0xFFFFFFFF));
    if (writeLe32(out_fd, crc) != 0) return 1;
    if (writeLe32(out_fd, isz) != 0) return 1;
    return 0;
}

fn doDecompress(in_fd: c_int, out_fd: c_int) u8 {
    var hdr: [10]u8 = undefined;
    var off: usize = 0;
    while (off < 10) {
        const n = core.c.read(in_fd, @as([*]u8, @ptrCast(&hdr)) + off, 10 - off);
        if (n <= 0) return 1;
        off += @intCast(n);
    }

    if (hdr[0] != 0x1F or hdr[1] != 0x8B) return core.die(1, "gzip: not in gzip format\n", .{});
    if (hdr[2] != 0) return core.die(1, "gzip: unsupported compression method\n", .{});
    // Skip extra fields
    const flg = hdr[3];
    if (flg & 0x04 != 0) {
        // FEXTRA
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

    if (stored_crc != actual_crc) return core.die(1, "gzip: crc error\n", .{});
    if (stored_size != actual_size) return core.die(1, "gzip: size error\n", .{});

    var pos: usize = 0;
    while (pos < data.len - 8) {
        const w = core.c.write(out_fd, data.ptr + pos, (data.len - 8) - pos);
        if (w < 0) return 1;
        pos += @intCast(w);
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var decompress = false;
    var file_arg: ?[]const u8 = null;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'd' => decompress = true,
                else => return core.die(1, "gzip: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    if (i < args.len) file_arg = args[i];

    if (decompress) {
        if (file_arg) |file| {
            if (std.mem.endsWith(u8, file, ".gz")) {
                var in_buf: [4096:0]u8 = undefined;
                if (file.len >= in_buf.len) return 1;
                @memcpy(in_buf[0..file.len], file);
                in_buf[file.len] = 0;
                const in_fd = core.c.open(in_buf[0..file.len :0].ptr, core.c.O_RDONLY);
                if (in_fd < 0) return core.die(1, "gzip: cannot open '{s}'\n", .{file});
                defer _ = core.c.close(in_fd);

                var out_buf: [4096:0]u8 = undefined;
                const out_name = file[0 .. file.len - 3];
                if (out_name.len >= out_buf.len) return 1;
                @memcpy(out_buf[0..out_name.len], out_name);
                out_buf[out_name.len] = 0;
                const out_fd = core.c.open(out_buf[0..out_name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
                if (out_fd < 0) return 1;
                defer _ = core.c.close(out_fd);

                return doDecompress(in_fd, out_fd);
            }
            return core.die(1, "gzip: unknown suffix\n", .{});
        } else {
            return doDecompress(0, 1);
        }
    } else {
        if (file_arg) |file| {
            var in_buf: [4096:0]u8 = undefined;
            if (file.len >= in_buf.len) return 1;
            @memcpy(in_buf[0..file.len], file);
            in_buf[file.len] = 0;
            const in_fd = core.c.open(in_buf[0..file.len :0].ptr, core.c.O_RDONLY);
            if (in_fd < 0) return core.die(1, "gzip: cannot open '{s}'\n", .{file});
            defer _ = core.c.close(in_fd);

            var out_buf: [4096:0]u8 = undefined;
            if (file.len + 3 >= out_buf.len) return 1;
            @memcpy(out_buf[0..file.len], file);
            out_buf[file.len..][0..3].* = ".gz".*;
            out_buf[file.len + 3] = 0;
            const out_fd = core.c.open(out_buf[0..file.len + 3 :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (out_fd < 0) return 1;
            defer _ = core.c.close(out_fd);

            return doCompress(in_fd, out_fd);
        } else {
            return doCompress(0, 1);
        }
    }
}
