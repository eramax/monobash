const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "zip", .main = main };

fn crc32(data: []const u8) u32 {
    var table: [256]u32 = undefined;
    for (&table, 0..) |*c, i| {
        var crc: u32 = @intCast(i);
        for (0..8) |_| crc = if (crc & 1 != 0) (crc >> 1) ^ 0xEDB88320 else crc >> 1;
        c.* = crc;
    }
    var crc: u32 = 0xFFFFFFFF;
    for (data) |b| crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFF;
}

fn writeLe16(fd: c_int, val: u16) u8 {
    const buf: [2]u8 = .{ @intCast(val & 0xFF), @intCast((val >> 8) & 0xFF) };
    const slice = &buf;
    var off: usize = 0;
    while (off < 2) {
        const w = core.c.write(fd, slice.ptr + off, 2 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
}

fn writeLe32(fd: c_int, val: u32) u8 {
    const buf: [4]u8 = .{ @intCast(val & 0xFF), @intCast((val >> 8) & 0xFF), @intCast((val >> 16) & 0xFF), @intCast((val >> 24) & 0xFF) };
    const slice = &buf;
    var off: usize = 0;
    while (off < 4) {
        const w = core.c.write(fd, slice.ptr + off, 4 - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
}

fn dosTime(ts: i64) u16 {
    const mt = @as(c_long, @intCast(ts));
    const tm = core.c.gmtime(&mt);
    if (tm == null) return 0;
    return @as(u16, @intCast(@as(u16, @intCast(tm.*.tm_hour)) << 11 | @as(u16, @intCast(tm.*.tm_min)) << 5 | @as(u16, @intCast(tm.*.tm_sec >> 1))));
}

fn dosDate(ts: i64) u16 {
    const mt = @as(c_long, @intCast(ts));
    const tm = core.c.gmtime(&mt);
    if (tm == null) return 0;
    const y: u32 = @intCast(tm.*.tm_year + 1900);
    const m: u32 = @intCast(tm.*.tm_mon + 1);
    const d: u32 = @intCast(tm.*.tm_mday);
    if (y < 1980) return (21 << 9) | (1 << 5) | 1;
    return @as(u16, @intCast(((y - 1980) << 9) | (m << 5) | d));
}

fn writeLocalHeader(fd: c_int, name: []const u8, crc: u32, comp_size: u32, uncomp_size: u32, dos_time: u16, dos_date: u16) u8 {
    if (writeLe32(fd, 0x04034b50) != 0) return 1;
    if (writeLe16(fd, 20) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, dos_time) != 0) return 1;
    if (writeLe16(fd, dos_date) != 0) return 1;
    if (writeLe32(fd, crc) != 0) return 1;
    if (writeLe32(fd, comp_size) != 0) return 1;
    if (writeLe32(fd, uncomp_size) != 0) return 1;
    if (writeLe16(fd, @intCast(name.len)) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    var off: usize = 0;
    while (off < name.len) {
        const w = core.c.write(fd, name.ptr + off, name.len - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
}

fn writeCentralEntry(fd: c_int, name: []const u8, crc: u32, comp_size: u32, uncomp_size: u32, dos_time: u16, dos_date: u16, mode: u32, local_offset: u32) u8 {
    if (writeLe32(fd, 0x02014b50) != 0) return 1;
    if (writeLe16(fd, 20) != 0) return 1;
    if (writeLe16(fd, 20) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, dos_time) != 0) return 1;
    if (writeLe16(fd, dos_date) != 0) return 1;
    if (writeLe32(fd, crc) != 0) return 1;
    if (writeLe32(fd, comp_size) != 0) return 1;
    if (writeLe32(fd, uncomp_size) != 0) return 1;
    if (writeLe16(fd, @intCast(name.len)) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe32(fd, mode) != 0) return 1;
    if (writeLe32(fd, local_offset) != 0) return 1;
    var off: usize = 0;
    while (off < name.len) {
        const w = core.c.write(fd, name.ptr + off, name.len - off);
        if (w < 0) return 1;
        off += @intCast(w);
    }
    return 0;
}

const FileEntry = struct {
    name: []const u8,
    data: []u8,
    crc: u32,
    dos_time: u16,
    dos_date: u16,
    mode: u32,
};

fn addFile(alloc: std.mem.Allocator, files: *std.ArrayListUnmanaged(FileEntry), path: []const u8) u8 {
    var path_buf: [4096:0]u8 = undefined;
    if (path.len >= path_buf.len) return 1;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z = path_buf[0..path.len :0];

    var st: core.c.struct_stat = undefined;
    if (core.c.lstat(path_z.ptr, &st) != 0) return 0;

    if (st.st_mode & core.c.S_IFMT == core.c.S_IFDIR) return 0;

    const fd = core.c.open(path_z.ptr, core.c.O_RDONLY);
    if (fd < 0) return 0;
    defer _ = core.c.close(fd);

    var data = std.ArrayListUnmanaged(u8).empty;
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = core.c.read(fd, &buf, buf.len);
        if (n < 0) break;
        if (n == 0) break;
        data.appendSlice(alloc, buf[0..@as(usize, @intCast(n))]) catch break;
    }

    const file_data = data.items;
    const dt = dosTime(@intCast(st.st_mtim.tv_sec));
    const dd = dosDate(@intCast(st.st_mtim.tv_sec));
    files.append(alloc, FileEntry{
        .name = alloc.dupe(u8, path) catch "",
        .data = file_data,
        .crc = crc32(file_data),
        .dos_time = dt,
        .dos_date = dd,
        .mode = @as(u32, @intCast(st.st_mode)),
    }) catch return 1;
    return 0;
}

fn addDir(alloc: std.mem.Allocator, files: *std.ArrayListUnmanaged(FileEntry), dir: []const u8, recursive: bool) void {
    var path_buf: [4096:0]u8 = undefined;
    if (dir.len >= path_buf.len) return;
    @memcpy(path_buf[0..dir.len], dir);
    path_buf[dir.len] = 0;
    const dir_z = path_buf[0..dir.len :0];

    const d = core.c.opendir(dir_z.ptr) orelse return;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        var sub_buf: [4096]u8 = undefined;
        const full = std.fmt.bufPrint(&sub_buf, "{s}/{s}", .{ dir, name }) catch continue;

        if (recursive) {
            var st_buf: core.c.struct_stat = undefined;
            var fzbuf: [4096:0]u8 = undefined;
            if (full.len >= fzbuf.len) continue;
            @memcpy(fzbuf[0..full.len], full);
            fzbuf[full.len] = 0;
            if (core.c.lstat(fzbuf[0..full.len :0].ptr, &st_buf) == 0 and st_buf.st_mode & core.c.S_IFMT == core.c.S_IFDIR) {
                addDir(alloc, files, full, true);
                continue;
            }
        }

        _ = addFile(alloc, files, full);
    }
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "zip: usage: zip [-r] ARCHIVE.zip FILES...\n", .{});

    const alloc = std.heap.page_allocator;
    var i: usize = 1;
    var recursive = false;
    var delete_mode = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'r' => recursive = true,
                'd' => delete_mode = true,
                else => return core.die(1, "zip: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    if (delete_mode) return core.die(1, "zip: delete not implemented\n", .{});

    if (i >= args.len) return core.die(1, "zip: missing archive name\n", .{});
    const archive = args[i];
    i += 1;

    var files = std.ArrayListUnmanaged(FileEntry).empty;

    while (i < args.len) {
        const path = args[i];
        i += 1;

        var st: core.c.struct_stat = undefined;
        var path_buf: [4096:0]u8 = undefined;
        if (path.len >= path_buf.len) continue;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;

        if (core.c.lstat(path_buf[0..path.len :0].ptr, &st) == 0 and st.st_mode & core.c.S_IFMT == core.c.S_IFDIR) {
            if (recursive) addDir(alloc, &files, path, true);
            continue;
        }

        _ = addFile(alloc, &files, path);
    }

    var archive_buf: [4096:0]u8 = undefined;
    if (archive.len >= archive_buf.len) return 1;
    @memcpy(archive_buf[0..archive.len], archive);
    archive_buf[archive.len] = 0;

    const fd = core.c.open(archive_buf[0..archive.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return core.die(1, "zip: cannot create '{s}'\n", .{archive});
    defer _ = core.c.close(fd);

    var local_offsets = std.ArrayListUnmanaged(u32).empty;
    var current_offset: u32 = 0;

    for (files.items) |file| {
        local_offsets.append(alloc, current_offset) catch return 1;
        if (writeLocalHeader(fd, file.name, file.crc, @as(u32, @intCast(file.data.len)), @as(u32, @intCast(file.data.len)), file.dos_time, file.dos_date) != 0) return 1;
        current_offset += @as(u32, @intCast(30 + file.name.len));

        var off: usize = 0;
        while (off < file.data.len) {
            const w = core.c.write(fd, file.data.ptr + off, file.data.len - off);
            if (w < 0) return 1;
            off += @intCast(w);
        }
        current_offset += @as(u32, @intCast(file.data.len));
    }

    const cd_offset = current_offset;

    for (files.items, 0..) |file, idx| {
        const local_off = local_offsets.items[idx];
        if (writeCentralEntry(fd, file.name, file.crc, @as(u32, @intCast(file.data.len)), @as(u32, @intCast(file.data.len)), file.dos_time, file.dos_date, file.mode, local_off) != 0) return 1;
        current_offset += @as(u32, @intCast(46 + file.name.len));
    }

    const cd_size = current_offset - cd_offset;

    if (writeLe32(fd, 0x06054b50) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;
    if (writeLe16(fd, @intCast(files.items.len)) != 0) return 1;
    if (writeLe16(fd, @intCast(files.items.len)) != 0) return 1;
    if (writeLe32(fd, cd_size) != 0) return 1;
    if (writeLe32(fd, cd_offset) != 0) return 1;
    if (writeLe16(fd, 0) != 0) return 1;

    for (files.items) |file| alloc.free(file.name);
    files.deinit(alloc);
    local_offsets.deinit(alloc);

    return 0;
}
