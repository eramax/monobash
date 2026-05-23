const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tar", .main = main };

fn octSet(buf: []u8, val: usize) void {
    var v = val;
    var i: usize = buf.len;
    while (i > 0) {
        i -= 1;
        buf[i] = @as(u8, @intCast('0' + (v & 7)));
        v >>= 3;
    }
}

fn octGet(buf: []const u8) usize {
    var val: usize = 0;
    for (buf) |c| {
        if (c >= '0' and c <= '7') val = (val << 3) | @as(usize, @intCast(c - '0'));
    }
    return val;
}

fn checksum(hdr: *const [512]u8) u32 {
    var sum: u32 = 0;
    for (hdr, 0..) |b, i| {
        sum += if (i >= 148 and i < 156) @as(u32, ' ') else @as(u32, b);
    }
    return sum;
}

fn createArchive(archive: [:0]const u8, files: [][]const u8) u8 {
    const fd = core.c.open(archive.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return core.die(1, "tar: cannot create '{s}'\n", .{archive});
    defer _ = core.c.close(fd);

    var hdr: [512]u8 = std.mem.zeroes([512]u8);
    var blk: [512]u8 = std.mem.zeroes([512]u8);
    var path_buf: [4096:0]u8 = undefined;
    var zero: [512]u8 = std.mem.zeroes([512]u8);
    var off: usize = 0;

    for (files) |file| {
        if (file.len >= path_buf.len) continue;
        @memcpy(path_buf[0..file.len], file);
        path_buf[file.len] = 0;
        const path_z = path_buf[0..file.len :0];

        var st: core.c.struct_stat = undefined;
        if (core.c.lstat(path_z.ptr, &st) != 0) {
            core.eprint("tar: cannot stat '{s}'\n", .{file});
            continue;
        }

        @memset(&hdr, 0);
        const name_bytes: []const u8 = file;
        @memcpy(hdr[0..@min(name_bytes.len, 100)], name_bytes[0..@min(name_bytes.len, 100)]);

        octSet(hdr[100..108], @as(usize, @intCast(st.st_mode & 0o777)));
        octSet(hdr[108..116], 0);
        octSet(hdr[116..124], 0);
        const file_size: usize = @intCast(@max(st.st_size, 0));
        octSet(hdr[124..136], file_size);
        octSet(hdr[136..148], @as(usize, @intCast(@max(st.st_mtim.tv_sec, 0))));

        @memcpy(hdr[257..262], "ustar");
        hdr[263] = '0';
        hdr[264] = '0';

        const chk = checksum(&hdr);
        const ckbuf = hdr[148..156];
        @memset(ckbuf, 0);
        octSet(ckbuf, chk);

        off = 0;
        while (off < 512) {
            const w = core.c.write(fd, @as([*]u8, @ptrCast(&hdr)) + off, 512 - off);
            if (w < 0) return 1;
            off += @intCast(w);
        }

        if (file_size > 0) {
            const ffd = core.c.open(path_z.ptr, core.c.O_RDONLY);
            if (ffd < 0) return 1;
            defer _ = core.c.close(ffd);

            var remaining = file_size;
            while (remaining > 0) {
                const to_read = @min(remaining, 512);
                const n = core.c.read(ffd, &blk, to_read);
                if (n <= 0) break;
                @memset(blk[@as(usize, @intCast(n))..512], 0);
                off = 0;
                while (off < 512) {
                    const w = core.c.write(fd, @as([*]u8, @ptrCast(&blk)) + off, 512 - off);
                    if (w < 0) return 1;
                    off += @intCast(w);
                }
                remaining -|= @intCast(n);
            }
        }
    }

    // End-of-archive: two zero blocks
    off = 0;
    while (off < 512) {
        const w = core.c.write(fd, @as([*]u8, @ptrCast(&zero)) + off, 512 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    off = 0;
    while (off < 512) {
        const w = core.c.write(fd, @as([*]u8, @ptrCast(&zero)) + off, 512 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
}

fn extractArchive(archive: [:0]const u8) u8 {
    const fd = core.c.open(archive.ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "tar: cannot open '{s}'\n", .{archive});
    defer _ = core.c.close(fd);

    var hdr: [512]u8 = undefined;
    var blk: [512]u8 = undefined;
    var rc: u8 = 0;

    while (true) {
        const n = core.c.read(fd, &hdr, 512);
        if (n < 512) break;

        // Check for end-of-archive (two zero blocks)
        if (hdr[0] == 0) break;

        const magic = hdr[257..263];
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[0])), 0);
        const size = octGet(hdr[124..136]);
        const mode = octGet(hdr[100..108]);

        if (!std.mem.eql(u8, magic, "ustar") and name.len == 0) break;

        var path_buf: [4096:0]u8 = undefined;
        if (name.len >= path_buf.len) { rc = 1; continue; }
        @memcpy(path_buf[0..name.len], name);
        path_buf[name.len] = 0;
        const path_z = path_buf[0..name.len :0];

        const typeflag = hdr[156];
        if (typeflag == '5') {
            // Directory
            _ = core.c.mkdir(path_z.ptr, @as(c_uint, @intCast(mode | 0o700)));
        } else {
            // Regular file
            const ofd = core.c.open(path_z.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, @intCast(mode)));
            if (ofd < 0) { rc = 1; continue; }
            defer _ = core.c.close(ofd);

            var remaining = size;
            while (remaining > 0) {
                const to_read = @min(remaining, 512);
                const n2 = core.c.read(fd, &blk, to_read);
                if (n2 <= 0) break;

                var off2: usize = 0;
                while (off2 < @as(usize, @intCast(n2))) {
                    const w = core.c.write(ofd, @as([*]u8, @ptrCast(&blk)) + off2, @as(usize, @intCast(n2)) - off2);
                    if (w < 0) break;
                    off2 += @intCast(w);
                }
                remaining -|= @as(usize, @intCast(n2));
            }
            // Skip padding
            const pad = (512 - (size % 512)) % 512;
            if (pad > 0) {
                var skip_buf: [512]u8 = undefined;
                _ = core.c.read(fd, &skip_buf, pad);
            }
        }
    }
    return rc;
}

fn listArchive(archive: [:0]const u8) u8 {
    const fd = core.c.open(archive.ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "tar: cannot open '{s}'\n", .{archive});
    defer _ = core.c.close(fd);

    var hdr: [512]u8 = undefined;

    while (true) {
        const n = core.c.read(fd, &hdr, 512);
        if (n < 512) break;
        if (hdr[0] == 0) break;

        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[0])), 0);
        const size = octGet(hdr[124..136]);
        const typeflag = hdr[156];

        if (name.len == 0) break;

        var line: [4096]u8 = undefined;
        const suffix = if (typeflag == '5') "/" else "";
        const s = std.fmt.bufPrint(&line, "{s}{s}\n", .{ name, suffix }) catch {
            core.writeAll(1, name);
            core.writeAll(1, "\n");
            continue;
        };
        core.writeAll(1, s);

        // Skip file data + padding
        const skip_total = size + (512 - (size % 512)) % 512;
        if (skip_total > 0) {
            var skip_buf: [4096]u8 = undefined;
            var to_skip = skip_total;
            while (to_skip > 0) {
                const r = @min(to_skip, skip_buf.len);
                const n2 = core.c.read(fd, &skip_buf, r);
                if (n2 <= 0) break;
                to_skip -|= @as(usize, @intCast(n2));
            }
        }
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "tar: usage: tar -cf|-xf|-tf ARCHIVE [FILES...]\n", .{});

    var i: usize = 1;
    var create = false;
    var extract = false;
    var list = false;
    var archive_name: ?[]const u8 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'c' => create = true,
                'x' => extract = true,
                't' => list = true,
                'f' => {
                    if (i + 1 < args.len and args[i].len == 2) {
                        archive_name = args[i + 1];
                        i += 1;
                    }
                },
                else => return core.die(1, "tar: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    const archive = archive_name orelse return core.die(1, "tar: missing archive name\n", .{});
    var buf: [4096:0]u8 = undefined;
    if (archive.len >= buf.len) return 1;
    @memcpy(buf[0..archive.len], archive);
    buf[archive.len] = 0;
    const archive_z = buf[0..archive.len :0];

    const files = args[i..];

    if (create) return createArchive(archive_z, files);
    if (extract) return extractArchive(archive_z);
    if (list) return listArchive(archive_z);
    return core.die(1, "tar: specify -c, -x, or -t\n", .{});
}
