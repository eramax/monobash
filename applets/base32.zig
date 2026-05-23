const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "base32", .main = main };

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

fn charVal(c: u8) ?u8 {
    return switch (c) {
        'A'...'Z' => c - 'A',
        'a'...'z' => c - 'a',
        '2'...'7' => c - '2' + 26,
        else => null,
    };
}

fn encode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const out_len = ((data.len + 4) / 5) * 8;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    while (i < data.len) {
        var buf: [5]u8 = [_]u8{0} ** 5;
        const chunk = @min(data.len - i, 5);
        @memcpy(buf[0..chunk], data[i..i + chunk]);
        const base = (i / 5) * 8;
        out[base + 0] = ALPHABET[(buf[0] >> 3) & 0x1F];
        out[base + 1] = ALPHABET[((buf[0] << 2) | (buf[1] >> 6)) & 0x1F];
        out[base + 2] = ALPHABET[(buf[1] >> 1) & 0x1F];
        out[base + 3] = ALPHABET[((buf[1] << 4) | (buf[2] >> 4)) & 0x1F];
        out[base + 4] = ALPHABET[((buf[2] << 1) | (buf[3] >> 7)) & 0x1F];
        out[base + 5] = ALPHABET[(buf[3] >> 2) & 0x1F];
        out[base + 6] = ALPHABET[((buf[3] << 3) | (buf[4] >> 5)) & 0x1F];
        out[base + 7] = ALPHABET[buf[4] & 0x1F];
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

fn decode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
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
            buf[j] = charVal(data[i + j]) orelse return error.InvalidChar;
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

pub fn main(args: [][]const u8) u8 {
    var decode_mode = false;
    var file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-d")) {
            decode_mode = true;
        } else if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            break;
        } else if (args[i].len > 0 and args[i][0] == '-') {
            return core.die(1, "base32: unknown option: {s}\n", .{args[i]});
        } else {
            file = args[i];
        }
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = if (file) |f| blk: {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return core.die(1, "base32: path too long\n", .{});
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "base32: {s}: No such file\n", .{f});
        defer _ = core.c.close(fd);
        break :blk core.readAll(alloc, fd, 1024 * 1024 * 16) catch return 1;
    } else (core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1);
    defer alloc.free(data);
    if (decode_mode) {
        const out = decode(data, alloc) catch return 1;
        defer alloc.free(out);
        core.writeAll(1, out);
    } else {
        const out = encode(data, alloc) catch return 1;
        defer alloc.free(out);
        core.writeAll(1, out);
        core.writeAll(1, "\n");
    }
    return 0;
}
