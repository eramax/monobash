const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ls", .main = main };

const Entry = struct {
    name: []const u8,
    size: i64,
    mtime: i64,
    mode: u32,
    nlink: u32,
    uid: u32,
    gid: u32,
};

fn modeToStr(mode: u32, buf: *[10]u8) void {
    buf[0] = switch (mode & core.c.S_IFMT) {
        core.c.S_IFDIR => 'd',
        core.c.S_IFLNK => 'l',
        core.c.S_IFSOCK => 's',
        core.c.S_IFIFO => 'p',
        core.c.S_IFBLK => 'b',
        core.c.S_IFCHR => 'c',
        else => '-',
    };
    buf[1] = if (mode & core.c.S_IRUSR != 0) 'r' else '-';
    buf[2] = if (mode & core.c.S_IWUSR != 0) 'w' else '-';
    const suid = mode & core.c.S_ISUID;
    buf[3] = if (mode & core.c.S_IXUSR != 0) (if (suid != 0) 's' else 'x') else (if (suid != 0) 'S' else '-');
    buf[4] = if (mode & core.c.S_IRGRP != 0) 'r' else '-';
    buf[5] = if (mode & core.c.S_IWGRP != 0) 'w' else '-';
    const sgid = mode & core.c.S_ISGID;
    buf[6] = if (mode & core.c.S_IXGRP != 0) (if (sgid != 0) 's' else 'x') else (if (sgid != 0) 'S' else '-');
    buf[7] = if (mode & core.c.S_IROTH != 0) 'r' else '-';
    buf[8] = if (mode & core.c.S_IWOTH != 0) 'w' else '-';
    const svtx = mode & core.c.S_ISVTX;
    buf[9] = if (mode & core.c.S_IXOTH != 0) (if (svtx != 0) 't' else 'x') else (if (svtx != 0) 'T' else '-');
}

fn humanSize(size: i64, buf: *[8]u8) []const u8 {
    const units = [_]u8{ 'K', 'M', 'G', 'T', 'P', 'E' };
    if (size < 1024) return std.fmt.bufPrint(buf, "{}", .{size}) catch "?";
    var s: f64 = @floatFromInt(size);
    for (units) |u| {
        s /= 1024.0;
        if (s < 1024.0) {
            return std.fmt.bufPrint(buf, "{d:.1}{c}", .{ s, u }) catch "?";
        }
    }
    return "?";
}

fn lessByName(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn lessBySize(_: void, a: Entry, b: Entry) bool {
    if (a.size != b.size) return a.size > b.size;
    return std.mem.lessThan(u8, a.name, b.name);
}

fn lessByTime(_: void, a: Entry, b: Entry) bool {
    if (a.mtime != b.mtime) return a.mtime > b.mtime;
    return std.mem.lessThan(u8, a.name, b.name);
}

fn listDir(path: [:0]const u8, long: bool, all: bool, human: bool, reverse: bool, time_sort: bool, size_sort: bool) u8 {
    const d = core.c.opendir(path.ptr) orelse return core.die(1, "ls: cannot open '{s}'\n", .{path});
    defer _ = core.c.closedir(d);

    var entries = std.heap.page_allocator.alloc(Entry, 4096) catch return 1;
    defer std.heap.page_allocator.free(entries);
    var count: usize = 0;

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (!all and name.len > 0 and name[0] == '.') continue;
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (count >= entries.len) continue;

        var path_buf: [4096:0]u8 = undefined;
        if (path.len + 1 + name.len >= path_buf.len) continue;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = '/';
        @memcpy(path_buf[path.len + 1 .. path.len + 1 + name.len], name);
        path_buf[path.len + 1 + name.len] = 0;
        const full_path = path_buf[0..path.len + 1 + name.len :0];

        var st: core.c.struct_stat = undefined;
        if (core.c.lstat(full_path.ptr, &st) != 0) continue;

        entries[count] = .{
            .name = std.heap.page_allocator.dupe(u8, name) catch continue,
            .size = @intCast(st.st_size),
            .mtime = @intCast(st.st_mtim.tv_sec),
            .mode = @intCast(st.st_mode),
            .nlink = @intCast(st.st_nlink),
            .uid = @intCast(st.st_uid),
            .gid = @intCast(st.st_gid),
        };
        count += 1;
    }

    if (count == 0) return 0;

    if (time_sort) {
        std.sort.block(Entry, entries[0..count], {}, lessByTime);
    } else if (size_sort) {
        std.sort.block(Entry, entries[0..count], {}, lessBySize);
    } else {
        std.sort.block(Entry, entries[0..count], {}, lessByName);
    }

    var i: usize = 0;
    if (reverse) {
        i = count;
        while (i > 0) {
            i -= 1;
            printEntry(&entries[i], long, human) catch {};
        }
    } else {
        while (i < count) {
            printEntry(&entries[i], long, human) catch {};
            i += 1;
        }
    }
    return 0;
}

fn printEntry(e: *const Entry, long: bool, human: bool) !void {
    var iobuf: [4096]u8 = undefined;
    if (long) {
        var modestr: [10]u8 = undefined;
        modeToStr(e.mode, &modestr);
        var owner: []const u8 = undefined;
        var ownbuf: [32]u8 = undefined;
        if (core.c.getpwuid(e.uid)) |pw| {
            owner = std.mem.sliceTo(pw[0].pw_name, 0);
        } else {
            owner = std.fmt.bufPrint(&ownbuf, "{}", .{e.uid}) catch "?";
        }
        var group: []const u8 = undefined;
        var grpbuf: [32]u8 = undefined;
        if (core.c.getgrgid(e.gid)) |gr| {
            group = std.mem.sliceTo(gr[0].gr_name, 0);
        } else {
            group = std.fmt.bufPrint(&grpbuf, "{}", .{e.gid}) catch "?";
        }
        var size_str: []const u8 = undefined;
        var sizebuf: [8]u8 = undefined;
        if (human) {
            size_str = humanSize(e.size, &sizebuf);
        } else {
            size_str = std.fmt.bufPrint(&sizebuf, "{}", .{e.size}) catch "?";
        }
        var t: i64 = e.mtime;
        const tm = core.c.localtime(&t) orelse return;
        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const mon = @as(usize, @intCast(tm[0].tm_mon));
        const line = std.fmt.bufPrint(&iobuf, "{s} {d: >3} {s} {s} {s: >8} {s} {d: >2} {d:0>2}:{d:0>2} {s}\n", .{
            modestr[0..10],
            e.nlink,
            owner,
            group,
            size_str,
            if (mon < 12) months[mon] else "???",
            tm[0].tm_mday,
            tm[0].tm_hour,
            tm[0].tm_min,
            e.name,
        }) catch return;
        core.writeAll(1, line);
    } else {
        const line = std.fmt.bufPrint(&iobuf, "{s}\n", .{e.name}) catch return;
        core.writeAll(1, line);
    }
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var long = false;
    var all = false;
    var human = false;
    var reverse = false;
    var time_sort = false;
    var size_sort = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'l' => long = true,
                'a' => all = true,
                'h' => human = true,
                'r' => reverse = true,
                't' => time_sort = true,
                'S' => size_sort = true,
                else => return core.die(1, "ls: invalid option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    if (i >= args.len) {
        var buf: [2:0]u8 = .{ '.', 0 };
        return listDir(&buf, long, all, human, reverse, time_sort, size_sort);
    }
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var path_buf: [4096:0]u8 = undefined;
        if (args[i].len >= path_buf.len) { rc = 1; continue; }
        @memcpy(path_buf[0..args[i].len], args[i]);
        path_buf[args[i].len] = 0;
        if (listDir(path_buf[0..args[i].len :0], long, all, human, reverse, time_sort, size_sort) != 0)
            rc = 1;
    }
    return rc;
}
