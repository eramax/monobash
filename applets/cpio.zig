const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cpio", .main = main };

fn hexVal(buf: []const u8) u32 {
    var val: u32 = 0;
    for (buf) |c| {
        val <<= 4;
        val += switch (c) {
            '0'...'9' => @as(u32, @intCast(c - '0')),
            'a'...'f' => @as(u32, @intCast(c - 'a' + 10)),
            'A'...'F' => @as(u32, @intCast(c - 'A' + 10)),
            else => 0,
        };
    }
    return val;
}

fn hexStr(val: u32, buf: []u8) void {
    for (0..buf.len) |i| {
        const shift: u5 = @intCast((buf.len - 1 - i) * 4);
        const nibble = (val >> shift) & 0xF;
        buf[i] = @intCast(if (nibble < 10) '0' + nibble else 'a' + nibble - 10);
    }
}

fn pad4(n: usize) usize {
    return (4 - (n & 3)) & 3;
}

fn mkdirAll(path: []const u8) void {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    for (0..path.len) |i| {
        if (buf[i] == '/') {
            buf[i] = 0;
            _ = core.c.mkdir(buf[0..i :0].ptr, 0o755);
            buf[i] = '/';
        }
    }
    _ = core.c.mkdir(buf[0..path.len :0].ptr, 0o755);
}

fn doList() u8 {
    const alloc = std.heap.page_allocator;
    const bytes = core.readAll(alloc, 0, 1 << 28) catch return 1;
    defer alloc.free(bytes);
    var pos: usize = 0;

    while (pos + 110 <= bytes.len) {
        const magic = bytes[pos..pos+6];
        if (!std.mem.eql(u8, magic, "070701")) break;

        const namesize = hexVal(bytes[pos+94..pos+102]);
        const filesize = hexVal(bytes[pos+54..pos+62]);
        const name_start = pos + 110;
        const name_end = name_start + @as(usize, @intCast(namesize));
        if (name_end > bytes.len) break;
        const name = std.mem.sliceTo(bytes[name_start..name_end], 0);

        if (std.mem.eql(u8, name, "TRAILER!!!")) break;

        core.writeAll(1, name);
        core.writeAll(1, "\n");

        const name_pad = pad4(110 + @as(usize, @intCast(namesize)));
        const data_start = name_end + name_pad;
        const data_end = data_start + @as(usize, @intCast(filesize));
        const data_pad = pad4(@as(usize, @intCast(filesize)));
        pos = data_end + data_pad;
    }

    return 0;
}

fn doExtract(create_dirs: bool) u8 {
    const alloc = std.heap.page_allocator;
    const bytes = core.readAll(alloc, 0, 1 << 28) catch return 1;
    defer alloc.free(bytes);
    var pos: usize = 0;

    while (pos + 110 <= bytes.len) {
        const magic = bytes[pos..pos+6];
        if (!std.mem.eql(u8, magic, "070701")) break;

        const mode = hexVal(bytes[pos+14..pos+22]);
        const filesize = hexVal(bytes[pos+54..pos+62]);
        const namesize = hexVal(bytes[pos+94..pos+102]);

        const name_start = pos + 110;
        const name_end = name_start + @as(usize, @intCast(namesize));
        if (name_end > bytes.len) break;
        const name = std.mem.sliceTo(bytes[name_start..name_end], 0);

        if (std.mem.eql(u8, name, "TRAILER!!!")) break;

        const name_pad = pad4(110 + @as(usize, @intCast(namesize)));
        const data_start = name_end + name_pad;
        const data_end = data_start + @as(usize, @intCast(filesize));
        const data_pad = pad4(@as(usize, @intCast(filesize)));

        if (name.len > 0) {
            var path_buf: [4096:0]u8 = undefined;
            if (name.len >= path_buf.len) { pos = data_end + data_pad; continue; }
            @memcpy(path_buf[0..name.len], name);
            path_buf[name.len] = 0;

            if (mode & core.c.S_IFMT == core.c.S_IFDIR) {
                if (create_dirs) mkdirAll(name);
            } else {
                if (create_dirs) {
                    const dir = std.fs.path.dirname(name) orelse "";
                    if (dir.len > 0) mkdirAll(dir);
                }
                const ofd = core.c.open(path_buf[0..name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, @intCast(mode & 0o777)));
                if (ofd >= 0) {
                    core.writeAll(ofd, bytes[data_start..data_start + @as(usize, @intCast(filesize))]);
                    _ = core.c.close(ofd);
                }
            }
        }

        pos = data_end + data_pad;
    }

    return 0;
}

fn doCreate() u8 {
    const alloc = std.heap.page_allocator;

    var header_buf: [110]u8 = undefined;

    var file_names = std.ArrayListUnmanaged([]u8).empty;
    const line_fd: c_int = 0;

    var reader = core.LineReader.init(line_fd);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch break;
        file_names.append(alloc, dup) catch break;
    }

    for (file_names.items) |file| {
        var path_buf: [4096:0]u8 = undefined;
        if (file.len >= path_buf.len) continue;
        @memcpy(path_buf[0..file.len], file);
        path_buf[file.len] = 0;

        var st: core.c.struct_stat = undefined;
        if (core.c.lstat(path_buf[0..file.len :0].ptr, &st) != 0) continue;

        @memset(&header_buf, '0');
        @memcpy(header_buf[0..6], "070701");
        hexStr(@as(u32, @intCast(st.st_ino)), header_buf[6..14]);
        hexStr(@as(u32, @intCast(st.st_mode)), header_buf[14..22]);
        hexStr(@as(u32, @intCast(st.st_uid)), header_buf[22..30]);
        hexStr(@as(u32, @intCast(st.st_gid)), header_buf[30..38]);
        hexStr(@as(u32, @intCast(st.st_nlink)), header_buf[38..46]);
        hexStr(@as(u32, @intCast(st.st_mtim.tv_sec)), header_buf[46..54]);

        if (st.st_mode & core.c.S_IFMT == core.c.S_IFDIR) {
            hexStr(0, header_buf[54..62]);
        } else {
            hexStr(@as(u32, @intCast(@max(st.st_size, 0))), header_buf[54..62]);
        }

        hexStr(0, header_buf[62..70]);
        hexStr(0, header_buf[70..78]);
        hexStr(0, header_buf[78..86]);
        hexStr(0, header_buf[86..94]);
        hexStr(@as(u32, @intCast(file.len + 1)), header_buf[94..102]);
        hexStr(0, header_buf[102..110]);

        core.writeAll(1, header_buf[0..110]);

        core.writeAll(1, file);
        core.writeAll(1, "\x00");
        var zero: [4]u8 = .{0, 0, 0, 0};
        const npad = pad4(110 + file.len + 1);
        if (npad > 0) {
            core.writeAll(1, zero[0..npad]);
        }

        if (st.st_mode & core.c.S_IFMT == core.c.S_IFREG) {
            const ffd = core.c.open(path_buf[0..file.len :0].ptr, core.c.O_RDONLY);
            if (ffd >= 0) {
                defer _ = core.c.close(ffd);
                var remaining: usize = @intCast(@max(st.st_size, 0));
                while (remaining > 0) {
                    const to_read = @min(remaining, 8192);
                    const chunk = core.readAll(std.heap.page_allocator, ffd, to_read) catch break;
                    defer std.heap.page_allocator.free(chunk);
                    if (chunk.len == 0) break;
                    core.writeAll(1, chunk);
                    remaining -= chunk.len;
                }
                const dpad = pad4(@intCast(@max(st.st_size, 0)));
                if (dpad > 0) {
                    core.writeAll(1, zero[0..dpad]);
                }
            }
        }
    }

    // TRAILER!!! entry
    @memset(&header_buf, '0');
    @memcpy(header_buf[0..6], "070701");
    hexStr(0, header_buf[6..14]);
    hexStr(0, header_buf[14..22]);
    hexStr(0, header_buf[22..30]);
    hexStr(0, header_buf[30..38]);
    hexStr(1, header_buf[38..46]);
    hexStr(0, header_buf[46..54]);
    hexStr(0, header_buf[54..62]);
    hexStr(0, header_buf[62..70]);
    hexStr(0, header_buf[70..78]);
    hexStr(0, header_buf[78..86]);
    hexStr(0, header_buf[86..94]);
    hexStr(@as(u32, 11), header_buf[94..102]);
    hexStr(0, header_buf[102..110]);

    core.writeAll(1, header_buf[0..110]);

    const trailer_bytes: [11]u8 = .{ 'T', 'R', 'A', 'I', 'L', 'E', 'R', '!', '!', '!', 0 };
    core.writeAll(1, trailer_bytes[0..]);

    const npad = pad4(110 + 11);
    if (npad > 0) {
        var zero: [4]u8 = .{0, 0, 0, 0};
        core.writeAll(1, zero[0..npad]);
    }

    for (file_names.items) |f| alloc.free(f);
    file_names.deinit(alloc);

    return 0;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "cpio: usage: cpio -i|-o|-t [-d]\n", .{});

    var i: usize = 1;
    var extract = false;
    var create = false;
    var list = false;
    var create_dirs = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'i' => extract = true,
                'o' => create = true,
                't' => list = true,
                'd' => create_dirs = true,
                else => return core.die(1, "cpio: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    if (list) return doList();
    if (extract) return doExtract(create_dirs);
    if (create) return doCreate();

    return core.die(1, "cpio: specify -i, -o, or -t\n", .{});
}
