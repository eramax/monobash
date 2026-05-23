const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "compress", .main = main };

const HASH_BITS: u32 = 13;
const HASH_SIZE: u32 = 1 << HASH_BITS;
const MAX_BITS: u32 = 12;
const MAX_CODE: u32 = (1 << MAX_BITS) - 1;
const CLEAR_CODE: u32 = 256;
const EOF_CODE: u32 = 257;
const FIRST_CODE: u32 = 258;

const BitWriter = struct {
    buf: [8192]u8,
    pos: usize,
    buf64: u64,
    bits_in_buf: u32,
    fd: c_int,

    fn init(fd: c_int) BitWriter {
        return .{ .buf = undefined, .pos = 0, .buf64 = 0, .bits_in_buf = 0, .fd = fd };
    }

    fn writeBits(self: *BitWriter, code: u32, nbits: u32) !void {
        self.buf64 |= (@as(u64, code) & ((@as(u64, 1) << @as(u6, @intCast(nbits))) - 1)) << @as(u6, @intCast(self.bits_in_buf));
        self.bits_in_buf += nbits;
        while (self.bits_in_buf >= 8) {
            if (self.pos >= self.buf.len) try self.flush();
            self.buf[self.pos] = @intCast(self.buf64 & 0xFF);
            self.pos += 1;
            self.buf64 >>= 8;
            self.bits_in_buf -= 8;
        }
    }

    fn flush(self: *BitWriter) !void {
        if (self.pos == 0) return;
        var off: usize = 0;
        while (off < self.pos) {
            const w = core.c.write(self.fd, @as([*]u8, @ptrCast(&self.buf)) + off, self.pos - off);
            if (w < 0) return error.WriteError;
            off += @intCast(w);
        }
        self.pos = 0;
        @memset(self.buf[0..], 0);
    }

    fn finish(self: *BitWriter) !void {
        if (self.bits_in_buf > 0) {
            if (self.pos >= self.buf.len) try self.flush();
            self.buf[self.pos] = @intCast(self.buf64 & 0xFF);
            self.pos += 1;
        }
        self.buf64 = 0;
        self.bits_in_buf = 0;
        try self.flush();
    }
};

const BitReader = struct {
    data: []const u8,
    bit_pos: usize,

    fn init(data: []const u8) BitReader {
        return .{ .data = data, .bit_pos = 0 };
    }

    fn readBits(self: *BitReader, nbits: u32) !u32 {
        var value: u32 = 0;
        var remaining = nbits;
        while (remaining > 0) {
            if (self.bit_pos >= self.data.len * 8) return error.EndOfStream;
            const byte_pos = self.bit_pos >> 3;
            const bit_off = self.bit_pos & 7;
            const bits_here = @as(u32, @intCast(@min(remaining, 8 - bit_off)));
            const mask = (@as(u32, 1) << @as(u5, @intCast(bits_here))) - 1;
            const byte = self.data[byte_pos] >> @intCast(bit_off);
            value |= (byte & mask) << @intCast(nbits - remaining);
            remaining -= bits_here;
            self.bit_pos += bits_here;
        }
        return value;
    }
};

fn compress(in_fd: c_int, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, in_fd) catch return 1;
    defer alloc.free(data);

    if (data.len == 0) {
        core.eprint("compress: empty input\n", .{});
        return 1;
    }

    const magic: [2]u8 = .{ 0x1F, 0x9D };
    var off: usize = 0;
    while (off < 2) {
        const w = core.c.write(out_fd, magic[off..].ptr, 2 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }

    const maxbits_buf: [1]u8 = .{MAX_BITS};
    for (0..1) |_| {
        const w = core.c.write(out_fd, &maxbits_buf, 1);
        if (w < 0) return 1;
        break;
    }

    var key_table: [HASH_SIZE]u32 = .{0xFFFFFFFF} ** HASH_SIZE;
    var val_table: [HASH_SIZE]u16 = undefined;

    var next_code: u32 = FIRST_CODE;
    var bits: u32 = 9;
    var max_val: u32 = (@as(u32, 1) << @as(u5, @intCast(bits))) - 1;

    var writer = BitWriter.init(out_fd);
    _ = writer.writeBits(CLEAR_CODE, bits) catch return 1;

    var prefix: u32 = data[0];

    for (data[1..]) |byte| {
        const key = (prefix << 8) | @as(u32, byte);
        var hash = (key * 307) & (HASH_SIZE - 1);

        var found = false;
        while (key_table[hash] != 0xFFFFFFFF) {
            if (key_table[hash] == key) {
                prefix = val_table[hash];
                found = true;
                break;
            }
            hash = (hash + 1) & (HASH_SIZE - 1);
        }

        if (!found) {
            _ = writer.writeBits(prefix, bits) catch return 1;

            if (next_code > MAX_CODE) {
                _ = writer.writeBits(CLEAR_CODE, bits) catch return 1;
                @memset(key_table[0..], 0xFFFFFFFF);
                next_code = FIRST_CODE;
                bits = 9;
                max_val = (@as(u32, 1) << @as(u5, @truncate(bits))) - 1;
            } else {
                if (next_code > max_val and bits < MAX_BITS) {
                    bits += 1;
                    max_val = (@as(u32, 1) << @as(u5, @truncate(bits))) - 1;
                }
                key_table[hash] = key;
                val_table[hash] = @intCast(next_code);
                next_code += 1;
            }
            prefix = byte;
        }
    }

    _ = writer.writeBits(prefix, bits) catch return 1;
    _ = writer.writeBits(EOF_CODE, bits) catch return 1;
    writer.finish() catch return 1;

    return 0;
}

fn decompress(in_fd: c_int, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, in_fd) catch return 1;
    defer alloc.free(data);

    if (data.len < 3 or data[0] != 0x1F or data[1] != 0x9D) return core.die(1, "compress: not in compress format\n", .{});

    const maxbits = data[2];
    _ = maxbits;

    var reader = BitReader.init(data[3..]);

    var bits: u32 = 9;
    var next_code: u32 = FIRST_CODE;

    var stack: [4096]u8 = undefined;
    var stack_pos: usize = 0;

    var prefix_table: [4096]u16 = undefined;
    var char_table: [4096]u8 = undefined;

    for (0..256) |i| {
        char_table[i] = @intCast(i);
    }

    var code = reader.readBits(bits) catch return 1;
    if (code == CLEAR_CODE) code = reader.readBits(bits) catch return 1;
    if (code == EOF_CODE) return 0;

    var old_code: u32 = code;
    var out_byte = char_table[@as(usize, @intCast(code))];
    var w: usize = 0;
    while (w < 1) {
        const n = core.c.write(out_fd, @as([*]u8, @ptrCast(&out_byte)) + w, 1 - w);
        if (n < 0) return 1;
        w += @intCast(n);
    }

    while (true) {
        code = reader.readBits(bits) catch return 1;
        if (code == EOF_CODE) return 0;

        var current = code;
        stack_pos = 0;

        if (code == CLEAR_CODE) {
            next_code = FIRST_CODE;
            bits = 9;
            code = reader.readBits(bits) catch return 1;
            if (code == EOF_CODE) return 0;
            old_code = code;
            out_byte = char_table[@as(usize, @intCast(code))];
            var woff: usize = 0;
            while (woff < 1) {
                const n = core.c.write(out_fd, @as([*]u8, @ptrCast(&out_byte)) + woff, 1 - woff);
                if (n < 0) return 1;
                woff += @intCast(n);
            }
            continue;
        }

        if (current >= next_code) {
            stack[stack_pos] = char_table[@as(usize, @intCast(old_code))];
            stack_pos += 1;
            current = old_code;
        }

        while (current >= 256) {
            stack[stack_pos] = char_table[@as(usize, @intCast(current))];
            stack_pos += 1;
            current = prefix_table[@as(usize, @intCast(current))];
        }
        stack[stack_pos] = char_table[@as(usize, @intCast(current))];
        stack_pos += 1;

        var si: usize = stack_pos;
        while (si > 0) {
            si -= 1;
            var woff: usize = 0;
            while (woff < 1) {
                const n = core.c.write(out_fd, @as([*]u8, @ptrCast(&stack[si])) + woff, 1 - woff);
                if (n < 0) return 1;
                woff += @intCast(n);
            }
        }

        const new_char = stack[stack_pos - 1];
        if (next_code <= MAX_CODE) {
            prefix_table[@as(usize, @intCast(next_code))] = @intCast(old_code);
            char_table[@as(usize, @intCast(next_code))] = new_char;
            next_code += 1;
        }

        if (next_code > (@as(u32, 1) << @as(u5, @intCast(bits))) and bits < MAX_BITS) {
            bits += 1;
        }

        old_code = code;
    }
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

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var do_decompress = false;
    var file_arg: ?[]const u8 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'd' => do_decompress = true,
                else => return core.die(1, "compress: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    if (i < args.len) file_arg = args[i];

    if (do_decompress) {
        if (file_arg) |file| {
            if (std.mem.endsWith(u8, file, ".Z")) {
                var in_buf: [4096:0]u8 = undefined;
                if (file.len >= in_buf.len) return 1;
                @memcpy(in_buf[0..file.len], file);
                in_buf[file.len] = 0;
                const in_fd = core.c.open(in_buf[0..file.len :0].ptr, core.c.O_RDONLY);
                if (in_fd < 0) return core.die(1, "compress: cannot open '{s}'\n", .{file});
                defer _ = core.c.close(in_fd);

                var out_buf: [4096:0]u8 = undefined;
                const out_name = file[0 .. file.len - 2];
                if (out_name.len >= out_buf.len) return 1;
                @memcpy(out_buf[0..out_name.len], out_name);
                out_buf[out_name.len] = 0;
                const out_fd = core.c.open(out_buf[0..out_name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
                if (out_fd < 0) return 1;
                defer _ = core.c.close(out_fd);

                return decompress(in_fd, out_fd);
            }
            return core.die(1, "compress: unknown suffix\n", .{});
        } else {
            return decompress(0, 1);
        }
    } else {
        if (file_arg) |file| {
            var in_buf: [4096:0]u8 = undefined;
            if (file.len >= in_buf.len) return 1;
            @memcpy(in_buf[0..file.len], file);
            in_buf[file.len] = 0;
            const in_fd = core.c.open(in_buf[0..file.len :0].ptr, core.c.O_RDONLY);
            if (in_fd < 0) return core.die(1, "compress: cannot open '{s}'\n", .{file});
            defer _ = core.c.close(in_fd);

            var out_buf: [4096:0]u8 = undefined;
            if (file.len + 2 >= out_buf.len) return 1;
            @memcpy(out_buf[0..file.len], file);
            out_buf[file.len..][0..2].* = ".Z".*;
            out_buf[file.len + 2] = 0;
            const out_fd = core.c.open(out_buf[0..file.len + 2 :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (out_fd < 0) return 1;
            defer _ = core.c.close(out_fd);

            return compress(in_fd, out_fd);
        } else {
            return compress(0, 1);
        }
    }
}
