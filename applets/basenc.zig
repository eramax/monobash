const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "basenc", .main = main };

const B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const B16_ALPHABET = "0123456789ABCDEF";

fn b64charVal(c: u8) ?u8 {
    return switch (c) {
        'A'...'Z' => c - 'A',
        'a'...'z' => c - 'a' + 26,
        '0'...'9' => c - '0' + 52,
        '+' => 62,
        '/' => 63,
        else => null,
    };
}

fn b32charVal(c: u8) ?u8 {
    return switch (c) {
        'A'...'Z' => c - 'A',
        'a'...'z' => c - 'a',
        '2'...'7' => c - '2' + 26,
        else => null,
    };
}

fn b16charVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}

fn b64encode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const out_len = ((data.len + 2) / 3) * 4;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    while (i < data.len) {
        var buf: [3]u8 = [_]u8{0} ** 3;
        const chunk = @min(data.len - i, 3);
        @memcpy(buf[0..chunk], data[i..i + chunk]);
        const base = (i / 3) * 4;
        out[base + 0] = B64_ALPHABET[(buf[0] >> 2) & 0x3F];
        out[base + 1] = B64_ALPHABET[((buf[0] << 4) | (buf[1] >> 4)) & 0x3F];
        out[base + 2] = B64_ALPHABET[((buf[1] << 2) | (buf[2] >> 6)) & 0x3F];
        out[base + 3] = B64_ALPHABET[buf[2] & 0x3F];
        if (chunk < 3) {
            const pad = 3 - chunk;
            var j: usize = 0;
            while (j < pad) : (j += 1)
                out[base + 3 - j] = '=';
        }
        i += 3;
    }
    return out;
}

fn b64decode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var end = data.len;
    while (end > 0 and data[end - 1] == '=') end -= 1;
    const out_len = (end * 3) / 4;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    var o: usize = 0;
    while (i < end) {
        var buf: [4]u8 = [_]u8{0} ** 4;
        const chunk = @min(end - i, 4);
        for (0..chunk) |j| {
            buf[j] = b64charVal(data[i + j]) orelse return error.InvalidChar;
        }
        out[o + 0] = (buf[0] << 2) | (buf[1] >> 4);
        if (o + 1 < out_len) out[o + 1] = (buf[1] << 4) | (buf[2] >> 2);
        if (o + 2 < out_len) out[o + 2] = (buf[2] << 6) | buf[3];
        i += 4;
        o += 3;
    }
    return out;
}

fn b32encode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const out_len = ((data.len + 4) / 5) * 8;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    while (i < data.len) {
        var buf: [5]u8 = [_]u8{0} ** 5;
        const chunk = @min(data.len - i, 5);
        @memcpy(buf[0..chunk], data[i..i + chunk]);
        const base = (i / 5) * 8;
        out[base + 0] = B32_ALPHABET[(buf[0] >> 3) & 0x1F];
        out[base + 1] = B32_ALPHABET[((buf[0] << 2) | (buf[1] >> 6)) & 0x1F];
        out[base + 2] = B32_ALPHABET[(buf[1] >> 1) & 0x1F];
        out[base + 3] = B32_ALPHABET[((buf[1] << 4) | (buf[2] >> 4)) & 0x1F];
        out[base + 4] = B32_ALPHABET[((buf[2] << 1) | (buf[3] >> 7)) & 0x1F];
        out[base + 5] = B32_ALPHABET[(buf[3] >> 2) & 0x1F];
        out[base + 6] = B32_ALPHABET[((buf[3] << 3) | (buf[4] >> 5)) & 0x1F];
        out[base + 7] = B32_ALPHABET[buf[4] & 0x1F];
        if (chunk < 5) {
            const pad: usize = switch (chunk) {
                1 => 6,
                2 => 4,
                3 => 3,
                4 => 1,
                else => 0,
            };
            var j: usize = 0;
            while (j < pad) : (j += 1)
                out[base + 8 - 1 - j] = '=';
        }
        i += 5;
    }
    return out;
}

fn b32decode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var end = data.len;
    while (end > 0 and data[end - 1] == '=') end -= 1;
    const out_len = (end * 5) / 8;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    var o: usize = 0;
    while (i < end) {
        var buf: [8]u8 = [_]u8{0} ** 8;
        const chunk = @min(end - i, 8);
        for (0..chunk) |j| {
            buf[j] = b32charVal(data[i + j]) orelse return error.InvalidChar;
        }
        out[o + 0] = (buf[0] << 3) | (buf[1] >> 2);
        if (o + 1 < out_len) out[o + 1] = (buf[1] << 6) | (buf[2] << 1) | (buf[3] >> 4);
        if (o + 2 < out_len) out[o + 2] = (buf[3] << 4) | (buf[4] >> 1);
        if (o + 3 < out_len) out[o + 3] = (buf[4] << 7) | (buf[5] << 2) | (buf[6] >> 3);
        if (o + 4 < out_len) out[o + 4] = (buf[6] << 5) | buf[7];
        i += 8;
        o += 5;
    }
    return out;
}

fn b16encode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var out = try alloc.alloc(u8, data.len * 2);
    for (data, 0..) |b, i| {
        out[i * 2 + 0] = B16_ALPHABET[(b >> 4) & 0xF];
        out[i * 2 + 1] = B16_ALPHABET[b & 0xF];
    }
    return out;
}

fn b16decode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    if (data.len % 2 != 0) return error.InvalidLength;
    var out = try alloc.alloc(u8, data.len / 2);
    for (0..out.len) |i| {
        const hi = b16charVal(data[i * 2]) orelse return error.InvalidChar;
        const lo = b16charVal(data[i * 2 + 1]) orelse return error.InvalidChar;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

const Mode = enum { base64, base32, base16 };

pub fn main(args: [][]const u8) u8 {
    var decode_mode = false;
    var mode: Mode = .base64;
    var file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-d")) {
            decode_mode = true;
        } else if (std.mem.eql(u8, args[i], "--base64")) {
            mode = .base64;
        } else if (std.mem.eql(u8, args[i], "--base32")) {
            mode = .base32;
        } else if (std.mem.eql(u8, args[i], "--base16")) {
            mode = .base16;
        } else if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            break;
        } else if (args[i].len > 0 and args[i][0] == '-') {
            return core.die(1, "basenc: unknown option: {s}\n", .{args[i]});
        } else {
            file = args[i];
        }
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = if (file) |f| blk: {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return core.die(1, "basenc: path too long\n", .{});
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "basenc: {s}: No such file\n", .{f});
        defer _ = core.c.close(fd);
        break :blk core.readAll(alloc, fd, 1024 * 1024 * 16) catch return 1;
    } else (core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1);
    defer alloc.free(data);
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    const result = if (decode_mode) blk: {
        break :blk switch (mode) {
            .base64 => b64decode(trimmed, alloc) catch return core.die(1, "basenc: invalid input\n", .{}),
            .base32 => b32decode(trimmed, alloc) catch return core.die(1, "basenc: invalid input\n", .{}),
            .base16 => b16decode(trimmed, alloc) catch return core.die(1, "basenc: invalid input\n", .{}),
        };
    } else blk: {
        break :blk switch (mode) {
            .base64 => b64encode(data, alloc) catch return 1,
            .base32 => b32encode(data, alloc) catch return 1,
            .base16 => b16encode(data, alloc) catch return 1,
        };
    };
    defer alloc.free(result);
    core.writeAll(1, result);
    if (!decode_mode) core.writeAll(1, "\n");
    return 0;
}
