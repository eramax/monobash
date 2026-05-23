const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "uuencode", .main = main };

const SRC_BUF_SIZE = 45;

const TBL_STD = [65]u8{
    '`', '!', '"', '#', '$', '%', '&', '\'',
    '(', ')', '*', '+', ',', '-', '.', '/',
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', ':', ';', '<', '=', '>', '?',
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W',
    'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
    '`',
};

const TBL_BASE64 = [65]u8{
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '+', '/',
    '=',
};

fn bbEncode(dst: []u8, src: []const u8, tbl: *const [65]u8) void {
    var p: usize = 0;
    var i: usize = 0;
    var length: i32 = @intCast(src.len);
    while (length > 0) {
        var s1: u8 = 0;
        var s2: u8 = 0;
        length -= 3;
        if (length >= -1) s1 = src[i + 1];
        if (length >= 0) s2 = src[i + 2];
        dst[p + 0] = tbl[src[i] >> 2];
        dst[p + 1] = tbl[((src[i] & 3) << 4) + (s1 >> 4)];
        dst[p + 2] = tbl[((s1 & 0xf) << 2) + (s2 >> 6)];
        dst[p + 3] = tbl[s2 & 0x3f];
        p += 4;
        i += 3;
    }
    while (length < 0) {
        p -= 1;
        dst[p] = tbl[64];
        length += 1;
    }
}

pub fn main(args: [][]const u8) u8 {
    var base64_mode = false;
    var ai: usize = 1;
    while (ai < args.len and args[ai][0] == '-') {
        const arg = args[ai];
        if (std.mem.eql(u8, arg, "-m")) {
            base64_mode = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            ai += 1;
            break;
        } else {
            return core.die(1, "uuencode: unknown option: {s}\n", .{arg});
        }
        ai += 1;
    }

    if (ai >= args.len) return core.die(1, "uuencode: missing filename argument\n", .{});

    const name_arg = args[ai];
    ai += 1;
    const file_arg: ?[]const u8 = if (ai < args.len) args[ai] else null;

    var fd: c_int = 0;
    var mode: u32 = undefined;

    if (file_arg) |fname| {
        var fbuf: [4096:0]u8 = undefined;
        if (fname.len >= fbuf.len) return core.die(1, "uuencode: path too long\n", .{});
        @memcpy(fbuf[0..fname.len], fname);
        fbuf[fname.len] = 0;
        fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "uuencode: {s}: No such file\n", .{fname});
        var st: core.c.struct_stat = undefined;
        if (core.c.fstat(fd, &st) == 0) {
            mode = @as(u32, @intCast(st.st_mode)) & 0o777;
        }
    } else {
        const old_mask = core.c.umask(0);
        mode = 0o666 & ~@as(u32, @intCast(old_mask));
        _ = core.c.umask(old_mask);
    }

    defer {
        if (file_arg != null and fd > 0) _ = core.c.close(fd);
    }

    const tbl: *const [65]u8 = if (base64_mode) &TBL_BASE64 else &TBL_STD;

    const alloc = std.heap.page_allocator;
    const hdr = if (base64_mode)
        std.fmt.allocPrint(alloc, "begin-base64 {o} {s}", .{ mode, name_arg }) catch ""
    else
        std.fmt.allocPrint(alloc, "begin {o} {s}", .{ mode, name_arg }) catch "";
    defer alloc.free(hdr);
    core.writeAll(1, hdr);

    var src_buf: [SRC_BUF_SIZE]u8 = undefined;
    var dst_buf: [4 * ((SRC_BUF_SIZE + 2) / 3)]u8 = undefined;

    while (true) {
        const n = core.c.read(fd, &src_buf, SRC_BUF_SIZE);
        if (n <= 0) break;
        const size = @as(usize, @intCast(n));

        bbEncode(&dst_buf, src_buf[0..size], tbl);
        const dst_len = 4 * ((size + 2) / 3);

        core.writeAll(1, "\n");
        if (!base64_mode) {
            const len_char = [_]u8{tbl[size]};
            core.writeAll(1, &len_char);
        }
        core.writeAll(1, dst_buf[0..dst_len]);
    }

    if (base64_mode) {
        core.writeAll(1, "\n====\n");
    } else {
        core.writeAll(1, "\n`\nend\n");
    }

    return 0;
}
