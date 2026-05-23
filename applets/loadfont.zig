const std = @import("std");
const core = @import("core.zig");
const PIO_FONT: u32 = 0x4B60;
const KDFONTOP: u32 = 0x4B72;
const KD_FONT_OP_SET: u32 = 0;
const PSF1_MAGIC0 = 0x36;
const PSF1_MAGIC1 = 0x04;
const PSF1_MODE512 = 0x01;
const PSF1_MODEHASTAB = 0x02;
const PSF1_MAXMODE = 0x05;
const PSF2_MAGIC0 = 0x72;
const PSF2_MAGIC1 = 0xb5;
const PSF2_MAGIC2 = 0x4a;
const PSF2_MAGIC3 = 0x86;
const ConsoleFontOp = extern struct {
    op: c_uint,
    flags: c_uint,
    width: c_uint,
    height: c_uint,
    charcount: c_uint,
    data: [*]u8,
};
const Psf2Hdr = extern struct {
    magic: [4]u8,
    version: u32,
    headersize: u32,
    flags: u32,
    length: u32,
    charsize: u32,
    height: u32,
    width: u32,
};
pub const meta = core.AppletMeta{ .name = "loadfont", .main = main };
pub fn main(_: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, core.c.STDIN_FILENO, 128 * 1024) catch return core.die(1, "loadfont: read error\n", .{});
    defer alloc.free(data);
    const fd = core.c.open("/dev/tty0", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "loadfont: cannot open /dev/tty0\n", .{});
    defer _ = core.c.close(fd);
    var font_data: []const u8 = data;
    var height: u32 = 32;
    var width: u32 = 8;
    var charsize: u32 = 32;
    var fontsize: u32 = 256;
    if (data.len >= 4 and data[0] == PSF1_MAGIC0 and data[1] == PSF1_MAGIC1) {
        const mode = data[2];
        if (mode > PSF1_MAXMODE) return core.die(1, "loadfont: unsupported PSF1 mode\n", .{});
        if (mode & PSF1_MODE512 != 0) fontsize = 512;
        height = data[3];
        charsize = data[3];
        font_data = data[4..];
    } else if (data.len >= @sizeOf(Psf2Hdr) and
        data[0] == PSF2_MAGIC0 and data[1] == PSF2_MAGIC1 and
        data[2] == PSF2_MAGIC2 and data[3] == PSF2_MAGIC3)
    {
        const h = @as(*align(1) const Psf2Hdr, @ptrCast(data.ptr));
        if (h.version > 0) return core.die(1, "loadfont: unsupported PSF2 version\n", .{});
        fontsize = h.length;
        charsize = h.charsize;
        height = h.height;
        width = h.width;
        font_data = data[h.headersize..];
    } else {
        if (data.len % 256 != 0 and data.len % 512 != 0)
            return core.die(1, "loadfont: bad font size\n", .{});
        height = @as(u32, @intCast(data.len / fontsize));
        charsize = height;
    }
    const char_width: u32 = 32 * ((width + 7) / 8);
    if (height < 1 or height > 32 or width < 1 or width > 32)
        return core.die(1, "loadfont: bad char size {d}x{d}\n", .{width, height});
    const min_font = if (fontsize < 128) @as(u32, 128) else fontsize;
    const buf_size = char_width * min_font;
    const buf = alloc.alloc(u8, buf_size) catch return 1;
    defer alloc.free(buf);
    @memset(buf, 0);
    const copy_n = @min(fontsize, min_font);
    for (0..copy_n) |j| {
        const src = font_data[j * charsize .. j * charsize + @min(charsize, char_width)];
        const dst = buf[j * char_width .. j * char_width + src.len];
        @memcpy(dst, src);
    }
    var cfo = ConsoleFontOp{
        .op = KD_FONT_OP_SET,
        .flags = 0,
        .width = width,
        .height = height,
        .charcount = fontsize,
        .data = buf.ptr,
    };
    if (core.c.ioctl(fd, KDFONTOP, &cfo) < 0) {
        if (core.c.ioctl(fd, PIO_FONT, buf.ptr) < 0)
            return core.die(1, "loadfont: PIO_FONT failed\n", .{});
    }
    return 0;
}
