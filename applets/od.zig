const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "od", .main = main };

pub fn main(args: [][]const u8) u8 {
    var addr_radix: u8 = 'o';
    var fmt_flag: u8 = 'o';
    var fmt_size: usize = 2;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--traditional")) { i += 1; continue; }
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        if (arg.len < 2) { i += 1; break; }

        if (arg[1] == 'A') {
            if (arg.len > 2) { addr_radix = arg[2]; i += 1; }
            else { i += 1; if (i < args.len) { addr_radix = args[i][0]; i += 1; } }
            continue;
        }
        if (arg[1] == 't') {
            var rest: []const u8 = &.{};
            if (arg.len > 2) { rest = arg[2..]; i += 1; }
            else { i += 1; if (i < args.len) { rest = args[i]; i += 1; } }
            if (rest.len > 0) {
                fmt_flag = rest[0];
                fmt_size = 2;
                if (rest.len > 1) {
                    fmt_size = switch (rest[1]) {
                        'C', 'c' => 1, 'S', 's' => 2, 'I', 'i' => 4, 'L', 'l' => 8,
                        else => std.fmt.parseInt(usize, rest[1..], 10) catch 2,
                    };
                }
            }
            continue;
        }

        const opt = arg[1];
        switch (opt) {
            'a' => { fmt_flag = 'a'; fmt_size = 1; },
            'b' => { fmt_flag = 'o'; fmt_size = 1; },
            'B' => { fmt_flag = 'o'; fmt_size = 2; },
            'c' => { fmt_flag = 'c'; fmt_size = 1; },
            'd' => { fmt_flag = 'u'; fmt_size = 2; },
            'D' => { fmt_flag = 'u'; fmt_size = 4; },
            'e' => { fmt_flag = 'f'; fmt_size = 8; },
            'f' => { fmt_flag = 'f'; fmt_size = 4; },
            'F' => { fmt_flag = 'f'; fmt_size = 8; },
            'h' => { fmt_flag = 'x'; fmt_size = 2; },
            'H' => { fmt_flag = 'x'; fmt_size = 4; },
            'i' => { fmt_flag = 'd'; fmt_size = 2; },
            'I' => { fmt_flag = 'd'; fmt_size = 8; },
            'l' => { fmt_flag = 'd'; fmt_size = 8; },
            'L' => { fmt_flag = 'd'; fmt_size = 8; },
            'o' => { fmt_flag = 'o'; fmt_size = 2; },
            'O' => { fmt_flag = 'o'; fmt_size = 4; },
            's' => { fmt_flag = 'd'; fmt_size = 2; },
            'u' => { fmt_flag = 'u'; fmt_size = 2; },
            'x' => { fmt_flag = 'x'; fmt_size = 2; },
            'X' => { fmt_flag = 'x'; fmt_size = 4; },
            else => return core.die(1, "od: unknown option: -{c}\n", .{opt}),
        }
        i += 1;
    }

    const files = args[i..];
    const alloc = std.heap.page_allocator;
    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
        defer alloc.free(data);
        dump(data, addr_radix, fmt_flag, fmt_size);
    } else {
        for (files) |f| {
            const fd = core.openReadName(f) orelse { core.eprint("od: cannot open '{s}'\n", .{f}); continue; };
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 1024 * 1024) catch continue;
            defer alloc.free(data);
            dump(data, addr_radix, fmt_flag, fmt_size);
        }
    }
    return 0;
}

fn pad(buf: []u8, val: []const u8, width: usize, right: bool) []const u8 {
    if (val.len >= width) return val[0..@min(val.len, width)];
    if (right) {
        // right-justified: spaces on left
        const spaces = width - val.len;
        for (0..spaces) |k| buf[k] = ' ';
        @memcpy(buf[spaces..][0..val.len], val);
        return buf[0..width];
    } else {
        @memcpy(buf[0..val.len], val);
        for (val.len..width) |k| buf[k] = ' ';
        return buf[0..width];
    }
}

fn dump(data: []const u8, addr_radix: u8, fmt_flag: u8, size: usize) void {
    const bpl: usize = 16;
    var lb: [4096]u8 = undefined;
    var pbuf: [64]u8 = undefined;
    var addr: usize = 0;

    while (addr < data.len) {
        var pos: usize = 0;
        // Address
        const addr_s = switch (addr_radix) {
            'd' => std.fmt.bufPrint(&pbuf, "{d}", .{addr}) catch "",
            'x' => std.fmt.bufPrint(&pbuf, "{x}", .{addr}) catch "",
            else => std.fmt.bufPrint(&pbuf, "{o}", .{addr}) catch "",
        };
        const astr = pad(&pbuf, addr_s, 7, true);
        @memcpy(lb[pos..][0..astr.len], astr);
        pos += astr.len;

        if (fmt_flag == 'a') {
            var bi: usize = 0;
            while (bi < bpl and addr + bi < data.len) : (bi += 1) {
                if (pos + 4 > lb.len) break;
                const e = namedEntry(data[addr + bi]);
                @memcpy(lb[pos..][0..e.len], e);
                pos += e.len;
            }
        } else if (fmt_flag == 'c') {
            var bi: usize = 0;
            while (bi < bpl and addr + bi < data.len) : (bi += 1) {
                if (pos + 4 > lb.len) break;
                const e = escapeEntry(data[addr + bi]);
                @memcpy(lb[pos..][0..e.len], e);
                pos += e.len;
            }
        } else if (fmt_flag == 'o' and size == 1) {
            var bi: usize = 0;
            while (bi < bpl and addr + bi < data.len) : (bi += 1) {
                const s = std.fmt.bufPrint(&pbuf, " {o:3}", .{data[addr + bi]}) catch "";
                if (pos + s.len > lb.len) break;
                @memcpy(lb[pos..][0..s.len], s);
                pos += s.len;
            }
        } else if (fmt_flag == 'o') {
            const ws = size;
            const nvals = @max(bpl / ws, 1);
            var wi: usize = 0;
            while (wi < nvals and addr + wi * ws < data.len) : (wi += 1) {
                const val = readIntLe(data, addr + wi * ws, ws);
                const s = std.fmt.bufPrint(&pbuf, " {o:0>6}", .{val}) catch "";
                if (pos + s.len > lb.len) break;
                @memcpy(lb[pos..][0..s.len], s);
                pos += s.len;
            }
        } else if (fmt_flag == 'x') {
            const ws = size;
            const nvals = @max(bpl / ws, 1);
            const digits = ws * 2;
            var wi: usize = 0;
            while (wi < nvals and addr + wi * ws < data.len) : (wi += 1) {
                const val = readIntLe(data, addr + wi * ws, ws);
                var hex_buf: [32]u8 = undefined;
                const hex_s = std.fmt.bufPrint(&hex_buf, "{x}", .{val}) catch "";
                lb[pos] = ' '; pos += 1;
                const padded = pad(&pbuf, hex_s, digits, true);
                if (pos + padded.len > lb.len) break;
                @memcpy(lb[pos..][0..padded.len], padded);
                pos += padded.len;
            }
        } else if (fmt_flag == 'd') {
            const ws = size;
            const nvals = @max(bpl / ws, 1);
            var wi: usize = 0;
            while (wi < nvals and addr + wi * ws < data.len) : (wi += 1) {
                const uv = readIntLe(data, addr + wi * ws, ws);
                var val: i64 = @bitCast(uv);
                if (ws < 8) { const shift: u6 = @intCast(64 - ws * 8); val = (val << shift) >> shift; }
                var ibuf: [32]u8 = undefined;
                const int_s = std.fmt.bufPrint(&ibuf, "{d}", .{val}) catch "";
                const w = if (ws == 2) @as(usize, 6) else @as(usize, 11);
                lb[pos] = ' '; pos += 1;
                const padded = pad(&pbuf, int_s, w, true);
                if (pos + padded.len > lb.len) break;
                @memcpy(lb[pos..][0..padded.len], padded);
                pos += padded.len;
            }
        } else if (fmt_flag == 'u') {
            const ws = size;
            const nvals = @max(bpl / ws, 1);
            var wi: usize = 0;
            while (wi < nvals and addr + wi * ws < data.len) : (wi += 1) {
                const val = readIntLe(data, addr + wi * ws, ws);
                var ibuf: [32]u8 = undefined;
                const int_s = std.fmt.bufPrint(&ibuf, "{d}", .{val}) catch "";
                const w = if (ws == 2) @as(usize, 5) else @as(usize, 10);
                lb[pos] = ' '; pos += 1;
                const padded = pad(&pbuf, int_s, w, true);
                if (pos + padded.len > lb.len) break;
                @memcpy(lb[pos..][0..padded.len], padded);
                pos += padded.len;
            }
        } else if (fmt_flag == 'f') {
            const ws = size;
            const nvals = @max(bpl / ws, 1);
            var wi: usize = 0;
            while (wi < nvals and addr + wi * ws < data.len) : (wi += 1) {
                lb[pos] = ' '; pos += 1;
                if (ws == 4) {
                    const val = readFloatLe(data, addr + wi * 4, 4);
                    var fbuf: [32]u8 = undefined;
                    const fs = std.fmt.bufPrint(&fbuf, "{e: >14.7}", .{val}) catch "";
                    if (pos + fs.len > lb.len) break;
                    @memcpy(lb[pos..][0..fs.len], fs);
                    pos += fs.len;
                } else {
                    const val = readFloatLe(data, addr + wi * 8, 8);
                    const s = std.fmt.bufPrint(&pbuf, "{e: >21.14}", .{val}) catch "";
                    if (pos + s.len > lb.len) break;
                    @memcpy(lb[pos..][0..s.len], s);
                    pos += s.len;
                }
            }
        }

        if (pos > 0 and pos < lb.len) { lb[pos] = '\n'; pos += 1; }
        core.writeAll(1, lb[0..pos]);
        addr += bpl;
    }

    if (data.len > 0 and addr_radix != 'n') {
        const addr_s = switch (addr_radix) {
            'd' => std.fmt.bufPrint(&pbuf, "{d}", .{data.len}) catch "",
            'x' => std.fmt.bufPrint(&pbuf, "{x}", .{data.len}) catch "",
            else => std.fmt.bufPrint(&pbuf, "{o}", .{data.len}) catch "",
        };
        const astr = pad(&pbuf, addr_s, 7, true);
        var pos: usize = astr.len;
        if (pos < lb.len) { lb[pos] = '\n'; pos += 1; }
        core.writeAll(1, lb[0..pos]);
    }
}

fn readIntLe(data: []const u8, offset: usize, size: usize) u64 {
    var val: u64 = 0;
    var i: usize = size;
    while (i > 0) {
        i -= 1;
        val = (val << 8) | (if (offset + i < data.len) @as(u64, data[offset + i]) else 0);
    }
    return val;
}

fn readFloatLe(data: []const u8, offset: usize, size: usize) f64 {
    if (size == 4) {
        var bytes: [4]u8 = .{0,0,0,0};
        for (0..4) |i| { if (offset + i < data.len) bytes[i] = data[offset + i]; }
        return @as(f32, @bitCast(bytes));
    }
    var bytes: [8]u8 = .{0,0,0,0,0,0,0,0};
    for (0..8) |i| { if (offset + i < data.len) bytes[i] = data[offset + i]; }
    return @bitCast(bytes);
}

fn namedEntry(byte: u8) []const u8 {
    const names = [_][]const u8{
        " nul", " soh", " stx", " etx", " eot", " enq", " ack", " bel",
        "  bs", "  ht", "  nl", "  vt", "  ff", "  cr", "  so", "  si",
        " dle", " dc1", " dc2", " dc3", " dc4", " nak", " syn", " etb",
        " can", "  em", " sub", " esc", "  fs", "  gs", "  rs", "  us",
    };
    if (byte < 32) return names[byte];
    if (byte == 127) return " del";
    if (byte >= 32 and byte < 127) {
        // 4-byte entry: space + space + space + char
        var buf: [4]u8 = .{ ' ', ' ', ' ', byte };
        return buf[0..4];
    }
    return " " ** 4;
}

fn escapeEntry(byte: u8) []const u8 {
    const s = switch (byte) {
        0 => " \\0",
        0x07 => " \\a",
        0x08 => " \\b",
        0x09 => " \\t",
        0x0a => " \\n",
        0x0b => " \\v",
        0x0c => " \\f",
        0x0d => " \\r",
        0x7f => " del",
        else => "",
    };
    if (s.len > 0) return s[0..4];
    if (byte >= 32 and byte < 127) {
        var buf: [4]u8 = .{ ' ', ' ', ' ', byte };
        return buf[0..4];
    }
    return " " ** 4;
}
