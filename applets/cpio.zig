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

fn printMode(mode: u32) void {
    const fmt = mode & core.c.S_IFMT;
    const ch: u8 = if (fmt == core.c.S_IFDIR) 'd' else if (fmt == core.c.S_IFLNK) 'l' else if (fmt == core.c.S_IFBLK) 'b' else if (fmt == core.c.S_IFCHR) 'c' else if (fmt == core.c.S_IFIFO) 'p' else if (fmt == core.c.S_IFSOCK) 's' else '-';
    var buf: [11]u8 = undefined;
    buf[0] = ch;
    buf[1] = if (mode & 0o400 != 0) 'r' else '-';
    buf[2] = if (mode & 0o200 != 0) 'w' else '-';
    buf[3] = if (mode & 0o100 != 0) 'x' else '-';
    buf[4] = if (mode & 0o040 != 0) 'r' else '-';
    buf[5] = if (mode & 0o020 != 0) 'w' else '-';
    buf[6] = if (mode & 0o010 != 0) 'x' else '-';
    buf[7] = if (mode & 0o004 != 0) 'r' else '-';
    buf[8] = if (mode & 0o002 != 0) 'w' else '-';
    buf[9] = if (mode & 0o001 != 0) 'x' else '-';
    buf[10] = ' ';
    core.writeAll(1, buf[0..]);
}

fn printUidGid(uid: u32, gid: u32) void {
    var buf: [64]u8 = undefined;
    if (uid == 0 and gid == 0) {
        core.writeAll(1, "0/0      ");
    } else {
        const s = std.fmt.bufPrint(&buf, "{d}/{d}", .{ uid, gid }) catch return;
        core.writeAll(1, s);
        var pad: usize = s.len;
        while (pad < 10) : (pad += 1) {
            core.writeAll(1, " ");
        }
    }
}

fn doList() u8 {
    return doListVerbose(false, -1, -1);
}

fn doListVerbose(verbose: bool, owner_uid: i32, owner_gid: i32) u8 {
    const alloc = std.heap.page_allocator;
    const bytes = core.readAll(alloc, 0, 1 << 28) catch return 1;
    defer alloc.free(bytes);
    var pos: usize = 0;
    var total_bytes: usize = 0;

    while (pos + 110 <= bytes.len) {
        const magic = bytes[pos..pos+6];
        if (!std.mem.eql(u8, magic, "070701")) break;

        const mode = hexVal(bytes[pos+14..pos+22]);
        const uid = hexVal(bytes[pos+22..pos+30]);
        const gid = hexVal(bytes[pos+30..pos+38]);
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
        const entry_size = 110 + @as(usize, @intCast(namesize)) + name_pad + @as(usize, @intCast(filesize)) + data_pad;
        total_bytes += entry_size;

        if (verbose) {
            printMode(mode);
            const display_uid: u32 = if (owner_uid >= 0) @intCast(owner_uid) else uid;
            const display_gid: u32 = if (owner_gid >= 0) @intCast(owner_gid) else gid;
            printUidGid(display_uid, display_gid);
            var szbuf: [16]u8 = undefined;
            const szs = std.fmt.bufPrint(&szbuf, "{d} ", .{filesize}) catch "";
            core.writeAll(1, szs);
        }

        core.writeAll(1, name);
        core.writeAll(1, "\n");

        pos = data_end + data_pad;
    }

    const blocks = (total_bytes + 511) / 512;
    var bbuf: [32]u8 = undefined;
    const bs = std.fmt.bufPrint(bbuf[0..], "{d} blocks\n", .{if (blocks < 1) @as(usize, 1) else blocks}) catch "";
    core.writeAll(1, bs);

    return 0;
}

fn doExtract(create_dirs: bool, ouid: i32, ogid: i32) u8 {
    _ = ouid; _ = ogid;
    const alloc = std.heap.page_allocator;
    const bytes = core.readAll(alloc, 0, 1 << 28) catch return 1;
    defer alloc.free(bytes);
    var pos: usize = 0;
    var total_bytes: usize = 0;

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
        const entry_size = 110 + @as(usize, @intCast(namesize)) + name_pad + @as(usize, @intCast(filesize)) + data_pad;
        total_bytes += entry_size;

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

    const blocks = (total_bytes + 511) / 512;
    var bbuf: [32]u8 = undefined;
    const bs = std.fmt.bufPrint(bbuf[0..], "{d} blocks\n", .{if (blocks < 1) @as(usize, 1) else blocks}) catch "";
    core.writeAll(1, bs);

    return 0;
}

fn doCreate(owner_uid: i32, owner_gid: i32) u8 {
    const alloc = std.heap.page_allocator;

    var header_buf: [110]u8 = undefined;

    var file_names = std.ArrayListUnmanaged([]u8).empty;
    const line_fd: c_int = 0;

    var reader = core.LineReader.init(line_fd);
    while (reader.next()) |line| {
        const dup = alloc.dupe(u8, line) catch break;
        file_names.append(alloc, dup) catch break;
    }

    var total_bytes: usize = 0;

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
        const use_uid: u32 = if (owner_uid >= 0) @intCast(owner_uid) else @intCast(st.st_uid);
        const use_gid: u32 = if (owner_gid >= 0) @intCast(owner_gid) else @intCast(st.st_gid);
        hexStr(use_uid, header_buf[22..30]);
        hexStr(use_gid, header_buf[30..38]);
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

        const this_hdr = 110 + file.len + 1 + npad;
        total_bytes += this_hdr;

        if (st.st_mode & core.c.S_IFMT == core.c.S_IFREG) {
            const fsize = @as(usize, @intCast(@max(st.st_size, 0)));
            const ffd = core.c.open(path_buf[0..file.len :0].ptr, core.c.O_RDONLY);
            if (ffd >= 0) {
                defer _ = core.c.close(ffd);
                var remaining: usize = fsize;
                while (remaining > 0) {
                    const to_read = @min(remaining, 8192);
                    const chunk = core.readAll(std.heap.page_allocator, ffd, to_read) catch break;
                    defer std.heap.page_allocator.free(chunk);
                    if (chunk.len == 0) break;
                    core.writeAll(1, chunk);
                    remaining -= chunk.len;
                }
                const dpad = pad4(fsize);
                if (dpad > 0) {
                    core.writeAll(1, zero[0..dpad]);
                }
                total_bytes += fsize + pad4(fsize);
            }
        }
    }

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
    total_bytes += 110 + 11 + npad;

    const blocks = (total_bytes + 511) / 512;
    var bbuf: [64]u8 = undefined;
    const bs = std.fmt.bufPrint(bbuf[0..], "{d} blocks\n", .{if (blocks < 1) @as(usize, 1) else blocks}) catch "";
    core.writeAll(2, bs);

    for (file_names.items) |f| alloc.free(f);
    file_names.deinit(alloc);

    return 0;
}

fn doPassThrough(dest_dir: []const u8, create_dirs: bool, owner_uid: i32, owner_gid: i32) u8 {
    const alloc = std.heap.page_allocator;

    const line_fd: c_int = 0;
    var reader = core.LineReader.init(line_fd);

    const sep: u8 = '/';
    var total_bytes: usize = 0;

    while (reader.next()) |line| {
        var path_buf: [4096:0]u8 = undefined;
        if (line.len >= path_buf.len) continue;

        @memcpy(path_buf[0..line.len], line);
        path_buf[line.len] = 0;

        var st: core.c.struct_stat = undefined;
        if (core.c.lstat(path_buf[0..line.len :0].ptr, &st) != 0) continue;

        _ = owner_uid;
        _ = owner_gid;

        total_bytes += 110 + line.len + 1 + pad4(110 + line.len + 1);
        if (st.st_mode & core.c.S_IFMT == core.c.S_IFREG) {
            const fsize = @as(usize, @intCast(@max(st.st_size, 0)));
            total_bytes += fsize + pad4(fsize);
        }

        var dest_path: [4096:0]u8 = undefined;
        const dlen: usize = dest_dir.len + 1 + line.len;
        if (dlen >= dest_path.len) continue;

        var src_offset: usize = 0;
        if (line.len > 0 and line[0] == '/') src_offset = 1;
        const rel_path = line[src_offset..];
        const rel_dlen = dest_dir.len + 1 + rel_path.len;
        if (rel_dlen >= dest_path.len) continue;
        @memcpy(dest_path[0..dest_dir.len], dest_dir);
        dest_path[dest_dir.len] = sep;
        @memcpy(dest_path[dest_dir.len + 1 ..][0..rel_path.len], rel_path);
        dest_path[rel_dlen] = 0;

        if (create_dirs) {
            const dir = std.fs.path.dirname(dest_path[0..rel_dlen]) orelse "";
            if (dir.len > 0) mkdirAll(dir);
        }

        if (st.st_mode & core.c.S_IFMT == core.c.S_IFDIR) {
            _ = core.c.mkdir(&dest_path, @as(c_uint, @intCast(st.st_mode & 0o777)));
        } else {
            const ofd = core.c.open(&dest_path, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, @intCast(st.st_mode & 0o777)));
            if (ofd >= 0) {
                const ffd2 = core.c.open(path_buf[0..line.len :0].ptr, core.c.O_RDONLY);
                if (ffd2 >= 0) {
                    defer _ = core.c.close(ffd2);
                    const data = core.readAll(alloc, ffd2, 1 << 20) catch {
                        _ = core.c.close(ofd);
                        continue;
                    };
                    defer alloc.free(data);
                    core.writeAll(ofd, data);
                }
                _ = core.c.close(ofd);
            }
        }
    }

    total_bytes += 110 + 11 + pad4(110 + 11);
    var bbuf: [64]u8 = undefined;
    const blocks = (total_bytes + 511) / 512;
    const bs = std.fmt.bufPrint(bbuf[0..], "{d} blocks\n", .{if (blocks < 1) @as(usize, 1) else blocks}) catch "";
    core.writeAll(2, bs);

    return 0;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "cpio: usage: cpio -i|-o|-t|-p [-d]\n", .{});

    var i: usize = 1;
    var extract = false;
    var create = false;
    var list = false;
    var pass_through = false;
    var create_dirs = false;
    var verbose = false;
    var owner_uid: i32 = -1;
    var owner_gid: i32 = -1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (args[i].len == 1) break;
        const cur_arg = args[i];
        var j: usize = 1;
        while (j < cur_arg.len) : (j += 1) {
            switch (cur_arg[j]) {
                'i' => extract = true,
                'o' => create = true,
                't' => list = true,
                'p' => pass_through = true,
                'd' => create_dirs = true,
                'v' => verbose = true,
                'u' => {},
                'm' => {},
                'H' => {
                    if (j + 1 < cur_arg.len) {
                        const fmt = cur_arg[j+1..];
                        if (!std.mem.eql(u8, fmt, "newc")) {}
                        j = cur_arg.len;
                    } else {
                        i += 1;
                        if (i < args.len) {
                            if (!std.mem.eql(u8, args[i], "newc")) {}
                        }
                    }
                },
                'R' => {
                    var remap_str: []const u8 = undefined;
                    if (j + 1 < cur_arg.len) {
                        remap_str = cur_arg[j+1..];
                        j = cur_arg.len;
                    } else {
                        i += 1;
                        if (i >= args.len) return core.die(1, "cpio: option requires an argument: -R\n", .{});
                        remap_str = args[i];
                    }
                    const colon = std.mem.indexOfScalar(u8, remap_str, ':') orelse return core.die(1, "cpio: invalid owner format\n", .{});
                    const uid_str = remap_str[0..colon];
                    const gid_str = remap_str[colon+1..];
                    owner_uid = @intCast(std.fmt.parseInt(i32, uid_str, 10) catch return core.die(1, "cpio: invalid uid\n", .{}));
                    owner_gid = @intCast(std.fmt.parseInt(i32, gid_str, 10) catch return core.die(1, "cpio: invalid gid\n", .{}));
                },
                else => return core.die(1, "cpio: unknown option '{c}'\n", .{cur_arg[j]}),
            }
        }
        i += 1;
    }

    if (pass_through) {
        if (i >= args.len) return core.die(1, "cpio: missing destination directory\n", .{});
        const dest_dir = args[i];
        i += 1;
        return doPassThrough(dest_dir, create_dirs, owner_uid, owner_gid);
    }

    if (list) return doListVerbose(verbose, owner_uid, owner_gid);
    if (extract) return doExtract(create_dirs, owner_uid, owner_gid);
    if (create) return doCreate(owner_uid, owner_gid);

    return core.die(1, "cpio: specify -i, -o, -p, or -t\n", .{});
}
