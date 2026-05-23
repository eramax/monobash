const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "md5sum", .main = main };

const S = [_]u32{
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
};

const K = [_]u32{
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
};

fn processBlock(a: *u32, b: *u32, c: *u32, d: *u32, w: *const [16]u32) void {
    var aa = a.*;
    var bb = b.*;
    var cc = c.*;
    var dd = d.*;
    var t: usize = 0;
    while (t < 64) : (t += 1) {
        var f: u32 = undefined;
        var g: usize = undefined;
        if (t < 16) {
            f = (bb & cc) | (~bb & dd);
            g = t;
        } else if (t < 32) {
            f = (dd & bb) | (~dd & cc);
            g = (5 * t + 1) % 16;
        } else if (t < 48) {
            f = bb ^ cc ^ dd;
            g = (3 * t + 5) % 16;
        } else {
            f = cc ^ (bb | ~dd);
            g = (7 * t) % 16;
        }
        f +%= aa +% K[t] +% w[g];
        aa = dd;
        dd = cc;
        cc = bb;
        bb +%= (f << @as(u5, @intCast(S[t]))) | (f >> @as(u5, @intCast(32 - S[t])));
    }
    a.* +%= aa;
    b.* +%= bb;
    c.* +%= cc;
    d.* +%= dd;
}

fn md5(data: []const u8) [16]u8 {
    var a: u32 = 0x67452301;
    var b: u32 = 0xefcdab89;
    var c: u32 = 0x98badcfe;
    var d: u32 = 0x10325476;
    const bit_len = @as(u64, data.len) * 8;

    var off: usize = 0;
    while (off + 64 <= data.len) {
        var w: [16]u32 = undefined;
        for (0..16) |j| {
            const p = off + j * 4;
            w[j] = @as(u32, data[p]) |
                (@as(u32, data[p + 1]) << 8) |
                (@as(u32, data[p + 2]) << 16) |
                (@as(u32, data[p + 3]) << 24);
        }
        processBlock(&a, &b, &c, &d, &w);
        off += 64;
    }

    var block: [128]u8 = undefined;
    const rem = data.len - off;
    @memcpy(block[0..rem], data[off..]);
    block[rem] = 0x80;
    var pos: usize = rem + 1;
    if (pos > 56) {
        while (pos < 64) { block[pos] = 0; pos += 1; }
        var w: [16]u32 = undefined;
        for (0..16) |j| {
            const p = j * 4;
            w[j] = @as(u32, block[p]) | (@as(u32, block[p + 1]) << 8) | (@as(u32, block[p + 2]) << 16) | (@as(u32, block[p + 3]) << 24);
        }
        processBlock(&a, &b, &c, &d, &w);
        pos = 0;
        while (pos < 56) { block[pos] = 0; pos += 1; }
    } else {
        while (pos < 56) { block[pos] = 0; pos += 1; }
    }
    @memcpy(block[56..64], std.mem.asBytes(&bit_len));
    var w: [16]u32 = undefined;
    for (0..16) |j| {
        const p = j * 4;
        w[j] = @as(u32, block[p]) | (@as(u32, block[p + 1]) << 8) | (@as(u32, block[p + 2]) << 16) | (@as(u32, block[p + 3]) << 24);
    }
    processBlock(&a, &b, &c, &d, &w);

    var result: [16]u8 = undefined;
    var idx: usize = 0;
    for ([_]u32{ a, b, c, d }) |v| {
        result[idx] = @as(u8, @truncate(v));
        result[idx + 1] = @as(u8, @truncate(v >> 8));
        result[idx + 2] = @as(u8, @truncate(v >> 16));
        result[idx + 3] = @as(u8, @truncate(v >> 24));
        idx += 4;
    }
    return result;
}

fn hex(buf: []u8, hash: [16]u8) []u8 {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0xF];
    }
    return buf[0..32];
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const files = args[1..];
    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1;
        defer alloc.free(data);
        const hash = md5(data);
        var hex_buf: [64]u8 = undefined;
        const h = hex(&hex_buf, hash);
        core.writeAll(1, h);
        core.writeAll(1, "  -\n");
        return 0;
    }
    var exit: u8 = 0;
    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) { exit = 1; continue; }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) { core.eprint("md5sum: {s}: No such file\n", .{f}); exit = 1; continue; }
        defer _ = core.c.close(fd);
        const data = core.readAll(alloc, fd, 1024 * 1024 * 16) catch { exit = 1; continue; };
        defer alloc.free(data);
        const hash = md5(data);
        var hex_buf: [64]u8 = undefined;
        const h = hex(&hex_buf, hash);
        core.writeAll(1, h);
        core.writeAll(1, "  ");
        core.writeAll(1, f);
        core.writeAll(1, "\n");
    }
    return exit;
}
