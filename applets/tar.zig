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

const Flags = struct {
    create: bool = false,
    extract: bool = false,
    list: bool = false,
    verbose: bool = false,
    gzip: bool = false,
    chdir: ?[]const u8 = null,
    overwrite: bool = false,
    keep: bool = false,
    archive: ?[]const u8 = null,
};

pub fn main(args: [][]const u8) u8 {
    var fl = Flags{};
    var i: usize = 1;
    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--")) { i += 1; break; }
        if (std.mem.eql(u8, a, "--overwrite")) { fl.overwrite = true; i += 1; continue; }
        // Handle both "tar -xvf" and "tar xvf" style
        const flags = if (a.len > 0 and a[0] == '-') a[1..] else a;
        // If flags don't look like tar flags (no dash, starts with letter), check if known
        if (flags.len == 0 or flags[0] == '-' or flags[0] == '/' or flags[0] == '.') break;
        // Check if the first char is a known flag
        const known = flags[0] == 'c' or flags[0] == 'x' or flags[0] == 't' or flags[0] == 'v' or flags[0] == 'z' or flags[0] == 'f' or flags[0] == 'C';
        if (!known) break;
        var consumed_next = false;
        for (flags) |c| {
            switch (c) {
                'c' => fl.create = true,
                'x' => fl.extract = true,
                't' => fl.list = true,
                'v' => fl.verbose = true,
                'z' => fl.gzip = true,
                'k' => fl.keep = true,
                'C' => { i += 1; if (i < args.len) fl.chdir = args[i]; consumed_next = true; },
                'f' => { i += 1; if (i < args.len) fl.archive = args[i]; consumed_next = true; },
                else => return core.die(1, "tar: unknown option '{c}'\n", .{c}),
            }
        }
        if (!consumed_next) i += 1;
        // After consuming f's argument, stop parsing flags
        if (fl.archive != null) { i += 1; break; }
    }
    const files = args[i..];

    if (fl.chdir) |cd| {
        var buf: [4096:0]u8 = undefined;
        if (cd.len < buf.len) {
            @memcpy(buf[0..cd.len], cd);
            buf[cd.len] = 0;
            _ = core.c.chdir(buf[0..cd.len :0].ptr);
        }
    }

    const alloc = std.heap.page_allocator;
    const archive_name: [:0]const u8 = if (fl.archive) |an| blk: {
        var buf: [4096:0]u8 = undefined;
        if (an.len >= buf.len) return 1;
        @memcpy(buf[0..an.len], an);
        buf[an.len] = 0;
        break :blk buf[0..an.len :0];
    } else "-";

    if (fl.create) return createArchive(&fl, archive_name, files, alloc);
    if (fl.extract) return extractArchive(&fl, archive_name, alloc);
    if (fl.list) return listArchive(&fl, archive_name, alloc);
    return core.die(1, "tar: specify -c, -x, or -t\n", .{});
}

fn openRead(name: [:0]const u8) ?c_int {
    if (std.mem.eql(u8, name, "-")) return 0;
    const fd = core.c.open(name.ptr, core.c.O_RDONLY);
    return if (fd >= 0) fd else null;
}

fn openWrite(name: [:0]const u8) ?c_int {
    if (std.mem.eql(u8, name, "-")) return 1;
    const fd = core.c.open(name.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    return if (fd >= 0) fd else null;
}

fn createArchive(_: *const Flags, archive: [:0]const u8, files: [][]const u8, alloc: std.mem.Allocator) u8 {
    const fd = openWrite(archive) orelse return core.die(1, "tar: cannot create '{s}'\n", .{archive});
    defer { if (!std.mem.eql(u8, archive, "-")) _ = core.c.close(fd); }

    var hdr: [512]u8 = std.mem.zeroes([512]u8);
    var zero: [512]u8 = std.mem.zeroes([512]u8);
    var path_buf: [4096:0]u8 = undefined;

    for (files) |file| {
        if (file.len == 0) continue;
        if (file.len >= path_buf.len) continue;
        @memcpy(path_buf[0..file.len], file);
        path_buf[file.len] = 0;
        const path_z = path_buf[0..file.len :0];

        // Sanitize: remove leading ./
        var clean = file;
        while (clean.len > 0 and (clean[0] == '.' and (clean.len == 1 or clean[1] == '/'))) {
            if (clean.len == 1) break;
            clean = if (clean[1] == '/') clean[2..] else clean;
        }

        if (tarAddFile(fd, &hdr, path_z, clean, alloc) != 0) {
            core.eprint("tar: cannot add '{s}'\n", .{file});
        }
    }

    core.writeAll(fd, zero[0..]);
    core.writeAll(fd, zero[0..]);
    return 0;
}

fn tarAddFile(fd: c_int, hdr: *[512]u8, path_z: [:0]const u8, name: []const u8, alloc: std.mem.Allocator) u8 {
    var st: core.c.struct_stat = undefined;
    if (core.c.lstat(path_z.ptr, &st) != 0) return 1;

    const is_dir = (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR;
    const is_lnk = (st.st_mode & core.c.S_IFMT) == core.c.S_IFLNK;
    const is_reg = (st.st_mode & core.c.S_IFMT) == core.c.S_IFREG;

    @memset(hdr, 0);
    const nlen = @min(name.len, 100);
    @memcpy(hdr[0..nlen], name[0..nlen]);

    octSet(hdr[100..108], @as(usize, @intCast(st.st_mode & 0o777)));
    octSet(hdr[108..116], @as(usize, @intCast(st.st_uid)));
    octSet(hdr[116..124], @as(usize, @intCast(st.st_gid)));

    if (is_lnk) {
        var lbuf: [4096]u8 = undefined;
        const n = core.c.readlink(path_z.ptr, &lbuf, lbuf.len);
        if (n > 0) {
            const ltarget = lbuf[0..@intCast(n)];
            @memcpy(hdr[157..][0..@min(ltarget.len, 100)], ltarget[0..@min(ltarget.len, 100)]);
        }
        hdr[156] = '2'; // symlink type
        octSet(hdr[124..136], 0);
    } else if (is_dir) {
        hdr[156] = '5'; // directory type
        octSet(hdr[124..136], 0);
    } else if (is_reg) {
        const file_size: usize = @intCast(@max(st.st_size, 0));
        octSet(hdr[124..136], file_size);

        // Check for hardlinks
        if (st.st_nlink > 1) {
            // Store as regular file for now (hardlink support would need inode tracking)
        }
    }

    // Timestamp
    octSet(hdr[136..148], @as(usize, @intCast(@max(st.st_mtim.tv_sec, 0))));

    // Magic
    @memcpy(hdr[257..262], "ustar");
    hdr[263] = '0'; // version
    hdr[264] = '0';

    // Uname/gname
    var pw: ?*core.c.struct_passwd = null;
    var gr: ?*core.c.struct_group = null;
    pw = core.c.getpwuid(st.st_uid);
    gr = core.c.getgrgid(st.st_gid);
    if (pw) |p| {
        const uname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&p.pw_name)), 0);
        @memcpy(hdr[265..][0..@min(uname.len, 32)], uname[0..@min(uname.len, 32)]);
    }
    if (gr) |g| {
        const gname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&g.gr_name)), 0);
        @memcpy(hdr[297..][0..@min(gname.len, 32)], gname[0..@min(gname.len, 32)]);
    }

    const chk = checksum(hdr);
    @memset(hdr[148..156], 0);
    octSet(hdr[148..156], chk);

    core.writeAll(fd, hdr[0..]);

    if (is_dir) {
        // Recurse into directory
        const d = core.c.opendir(path_z.ptr) orelse return 0;
        defer _ = core.c.closedir(d);
        while (true) {
            const entry = core.c.readdir(d) orelse break;
            const dirent = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
            const ename = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
            if (std.mem.eql(u8, ename, ".") or std.mem.eql(u8, ename, "..")) continue;
            const sub_name = tryJoin(name, ename, alloc) catch continue;
            defer alloc.free(sub_name);
            const sub_path = tryJoin(path_z, ename, alloc) catch continue;
            defer alloc.free(sub_path);
            var sbuf: [4096:0]u8 = undefined;
            if (sub_path.len >= sbuf.len) continue;
            @memcpy(sbuf[0..sub_path.len], sub_path);
            sbuf[sub_path.len] = 0;
            _ = tarAddFile(fd, hdr, sbuf[0..sub_path.len :0], sub_name, alloc);
        }
        return 0;
    }

    if (is_lnk) return 0;

    // Write file content
    if (is_reg) {
        const file_size: usize = @intCast(@max(st.st_size, 0));
        if (file_size > 0) {
            const ffd = core.c.open(path_z.ptr, core.c.O_RDONLY);
            if (ffd < 0) return 1;
            defer _ = core.c.close(ffd);

            var blk2: [512]u8 = std.mem.zeroes([512]u8);
            var remaining = file_size;
            while (remaining > 0) {
                const to_read = @min(remaining, 512);
                const chunk = core.readAll(alloc, ffd, to_read) catch break;
                defer alloc.free(chunk);
                if (chunk.len == 0) break;
                @memset(&blk2, 0);
                @memcpy(blk2[0..chunk.len], chunk);
                core.writeAll(fd, blk2[0..512]);
                remaining -|= chunk.len;
            }
            // Padding
            const pad = (512 - (file_size % 512)) % 512;
            if (pad > 0) {
                const zero: [512]u8 = std.mem.zeroes([512]u8);
                core.writeAll(fd, zero[0..pad]);
            }
        }
    }

    return 0;
}

fn tryJoin(a: []const u8, b: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayListAligned(u8, null).empty;
    try result.appendSlice(alloc, a);
    try result.append(alloc, '/');
    try result.appendSlice(alloc, b);
    return result.toOwnedSlice(alloc);
}

fn extractArchive(fl: *const Flags, archive: [:0]const u8, alloc: std.mem.Allocator) u8 {
    const fd = openRead(archive) orelse return core.die(1, "tar: cannot open '{s}'\n", .{archive});
    defer { if (!std.mem.eql(u8, archive, "-")) _ = core.c.close(fd); }

    var hdr: [512]u8 = undefined;
    var rc: u8 = 0;
    var hdr_data: []u8 = undefined;
    var hdr_alloc = false;

    while (true) {
        if (hdr_alloc) alloc.free(hdr_data);
        hdr_alloc = false;
        hdr_data = core.readAll(alloc, fd, 512) catch break;
        if (hdr_data.len < 512) {
            if (!hdr_alloc) {
                core.eprint("tar: short read\n", .{});
                rc = 1;
            }
            break;
        }
        hdr_alloc = true;
        @memcpy(&hdr, hdr_data[0..512]);

        if (hdr[0] == 0) break;

        const magic = hdr[257..263];
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[0])), 0);
        const size = octGet(hdr[124..136]);
        const mode = octGet(hdr[100..108]);
        const typeflag = hdr[156];

        if (!std.mem.eql(u8, magic, "ustar") and name.len == 0) break;

        // Skip /../ path traversal
        var safe = name;
        while (std.mem.indexOf(u8, safe, "/../")) |idx| {
            safe = safe[idx + 3 ..];
        }
        while (std.mem.startsWith(u8, safe, "../")) safe = safe[3..];
        while (std.mem.startsWith(u8, safe, "/")) safe = safe[1..];

        if (safe.len == 0) {
            // Skip data
            skipTarData(fd, size, alloc);
            continue;
        }

        var path_buf: [4096:0]u8 = undefined;
        if (safe.len >= path_buf.len) { rc = 1; skipTarData(fd, size, alloc); continue; }
        @memcpy(path_buf[0..safe.len], safe);
        path_buf[safe.len] = 0;
        const path_z = path_buf[0..safe.len :0];

        if (fl.verbose) {
            core.writeAll(1, safe);
            if (typeflag == '5') core.writeAll(1, "/");
            core.writeAll(1, "\n");
        }

        switch (typeflag) {
            '5' => { // Directory
                _ = core.c.mkdir(path_z.ptr, @as(c_uint, @intCast(mode | 0o700)));
            },
            '2' => { // Symlink
                const target = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[157])), 0);
                _ = core.c.unlink(path_z.ptr);
                if (core.c.symlink(target.ptr, path_z.ptr) < 0) {
                    core.eprint("tar: can't create symlink '{s}' to '{s}'\n", .{safe, target});
                    rc = 1;
                }
                skipTarData(fd, size, alloc);
            },
            '1' => { // Hardlink
                const target = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[157])), 0);
                var tbuf: [4096:0]u8 = undefined;
                if (target.len < tbuf.len) {
                    @memcpy(tbuf[0..target.len], target);
                    tbuf[target.len] = 0;
                    _ = core.c.link(tbuf[0..target.len :0].ptr, path_z.ptr);
                }
                skipTarData(fd, size, alloc);
            },
            else => { // Regular file (type '0' or '\0')
                // Remove existing file if not keeping
                if (!fl.keep) {
                    if (fl.overwrite) {
                        // Don't unlink, just open for writing
                    } else {
                        _ = core.c.unlink(path_z.ptr);
                    }
                }
                const open_flags = if (fl.keep) core.c.O_WRONLY | core.c.O_CREAT | core.c.O_EXCL else core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC;
                var ofd = core.c.open(path_z.ptr, open_flags, @as(c_uint, @intCast(mode)));
                if (ofd < 0) {
                    // Try creating parent dir
                    var pbuf: [4096]u8 = undefined;
                    var last_slash: usize = safe.len;
                    while (last_slash > 0) {
                        last_slash -= 1;
                        if (safe[last_slash] == '/') break;
                    }
                    if (last_slash > 0) {
                        @memcpy(pbuf[0..last_slash], safe[0..last_slash]);
                        pbuf[last_slash] = 0;
                        _ = core.c.mkdir(pbuf[0..last_slash :0].ptr, 0o755);
                    }
                    ofd = core.c.open(path_z.ptr, open_flags, @as(c_uint, @intCast(mode)));
                }
                if (ofd < 0) { rc = 1; skipTarData(fd, size, alloc); continue; }
                defer _ = core.c.close(ofd);

                var remaining = size;
                while (remaining > 0) {
                    const to_read = @min(remaining, 512);
                    const chunk = core.readAll(alloc, fd, to_read) catch break;
                    defer alloc.free(chunk);
                    if (chunk.len == 0) break;
                    core.writeAll(ofd, chunk);
                    remaining -|= chunk.len;
                }
                const pad = (512 - (size % 512)) % 512;
                if (pad > 0) {
                    if (core.readAll(alloc, fd, pad)) |skip_data| alloc.free(skip_data) else |_| {}
                }
            },
        }
    }
    if (hdr_alloc) alloc.free(hdr_data);
    return rc;
}

fn skipTarData(fd: c_int, size: usize, alloc: std.mem.Allocator) void {
    const total = size + (512 - (size % 512)) % 512;
    var remaining = total;
    while (remaining > 0) {
        const to_read = @min(remaining, 4096);
        if (core.readAll(alloc, fd, to_read)) |data| alloc.free(data) else |_| break;
        remaining -|= to_read;
    }
}

fn listArchive(fl: *const Flags, archive: [:0]const u8, alloc: std.mem.Allocator) u8 {
    const fd = openRead(archive) orelse return core.die(1, "tar: cannot open '{s}'\n", .{archive});
    defer { if (!std.mem.eql(u8, archive, "-")) _ = core.c.close(fd); }

    var hdr: [512]u8 = undefined;
    var hdr_data: []u8 = undefined;
    var hdr_alloc = false;

    while (true) {
        if (hdr_alloc) alloc.free(hdr_data);
        hdr_alloc = false;
        hdr_data = core.readAll(alloc, fd, 512) catch break;
        if (hdr_data.len < 512) break;
        hdr_alloc = true;
        @memcpy(&hdr, hdr_data[0..512]);
        if (hdr[0] == 0) break;

        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[0])), 0);
        const size = octGet(hdr[124..136]);
        const typeflag = hdr[156];
        const magic = hdr[257..263];

        if (!std.mem.eql(u8, magic, "ustar") and name.len == 0) break;

        if (fl.verbose) {
            // Verbose listing: perms + uname/gname + size + date + name
            const mode = octGet(hdr[100..108]);
            var line: [512]u8 = undefined;
            var pos: usize = 0;
            // Permission string
            const perms = modeToStr(mode, typeflag);
            @memcpy(line[pos..][0..perms.len], perms);
            pos += perms.len;
            line[pos] = ' '; pos += 1;
            // Uname/gname
            const uname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[265])), 0);
            const gname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[297])), 0);
            if (uname.len > 0) {
                @memcpy(line[pos..][0..uname.len], uname);
                pos += uname.len;
            } else { line[pos] = '0'; pos += 1; }
            line[pos] = '/'; pos += 1;
            if (gname.len > 0) {
                @memcpy(line[pos..][0..gname.len], gname);
                pos += gname.len;
            } else { line[pos] = '0'; pos += 1; }
            // Pad to column
            while (pos < 32) { line[pos] = ' '; pos += 1; }
            // Size
            var sb: [16]u8 = undefined;
            const ss = std.fmt.bufPrint(&sb, "{d:8} ", .{size}) catch "";
            @memcpy(line[pos..][0..ss.len], ss);
            pos += ss.len;
            // Name
            @memcpy(line[pos..][0..name.len], name);
            pos += name.len;
            if (typeflag == '2') {
                // Symlink target
                const target = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[157])), 0);
                line[pos] = ' '; pos += 1;
                line[pos] = '-'; pos += 1;
                line[pos] = '>'; pos += 1;
                line[pos] = ' '; pos += 1;
                @memcpy(line[pos..][0..target.len], target);
                pos += target.len;
            } else if (typeflag == '1') {
                const target = std.mem.sliceTo(@as([*c]u8, @ptrCast(&hdr[157])), 0);
                line[pos] = ' '; pos += 1;
                line[pos] = '-'; pos += 1;
                line[pos] = '>'; pos += 1;
                line[pos] = ' '; pos += 1;
                @memcpy(line[pos..][0..target.len], target);
                pos += target.len;
            }
            line[pos] = '\n'; pos += 1;
            core.writeAll(1, line[0..pos]);
        } else {
            core.writeAll(1, name);
            if (typeflag == '5') core.writeAll(1, "/");
            core.writeAll(1, "\n");
        }

        // Skip data
        const skip_total = size + (512 - (size % 512)) % 512;
        if (skip_total > 0) {
            var remaining = skip_total;
            while (remaining > 0) {
                const r = @min(remaining, 4096);
                if (core.readAll(alloc, fd, r)) |data| alloc.free(data) else |_| break;
                remaining -|= r;
            }
        }
    }
    if (hdr_alloc) alloc.free(hdr_data);
    return 0;
}

fn modeToStr(mode: usize, typeflag: u8) []const u8 {
    var buf: [11]u8 = undefined;
    const ft: u8 = if (typeflag == '5') 'd' else if (typeflag == '2') 'l' else '-';
    buf[0] = ft;
    buf[1] = if (mode & 0o400 != 0) 'r' else '-';
    buf[2] = if (mode & 0o200 != 0) 'w' else '-';
    buf[3] = if (mode & 0o100 != 0) 'x' else '-';
    buf[4] = if (mode & 0o040 != 0) 'r' else '-';
    buf[5] = if (mode & 0o020 != 0) 'w' else '-';
    buf[6] = if (mode & 0o010 != 0) 'x' else '-';
    buf[7] = if (mode & 0o004 != 0) 'r' else '-';
    buf[8] = if (mode & 0o002 != 0) 'w' else '-';
    buf[9] = if (mode & 0o001 != 0) 'x' else '-';
    buf[10] = 0;
    return buf[0..10];
}
