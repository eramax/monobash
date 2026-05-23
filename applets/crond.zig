const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "crond", .main = main };

fn fieldMatches(field: []const u8, value: u32) bool {
    if (std.mem.indexOfScalar(u8, field, ',')) |_| {
        var it = std.mem.tokenizeScalar(u8, field, ',');
        while (it.next()) |part| {
            if (fieldMatches(part, value)) return true;
        }
        return false;
    }
    if (field.len >= 2 and field[0] == '*' and field[1] == '/') {
        const step = std.fmt.parseInt(u32, field[2..], 10) catch return false;
        return if (step == 0) false else value % step == 0;
    }
    if (std.mem.indexOfScalar(u8, field, '-')) |dash| {
        const lo = std.fmt.parseInt(u32, field[0..dash], 10) catch return false;
        const hi = std.fmt.parseInt(u32, field[dash + 1 ..], 10) catch return false;
        return value >= lo and value <= hi;
    }
    if (field.len == 1 and field[0] == '*') return true;
    const n = std.fmt.parseInt(u32, field, 10) catch return false;
    return n == value;
}

fn processFile(path: []const u8, is_system: bool, current_min: u32, current_hr: u32, current_day: u32, current_mon: u32, current_wk: u32) void {
    var zpath: [4096:0]u8 = undefined;
    if (path.len >= zpath.len) return;
    @memcpy(zpath[0..path.len], path);
    zpath[path.len] = 0;
    const fd = core.c.open(zpath[0..path.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);

    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return;
    defer std.heap.page_allocator.free(data);

    var pos: usize = 0;
    while (pos < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[pos..], '\n') orelse (data.len - pos);
        const line = std.mem.trim(u8, data[pos..][0..nl], &[_]u8{' ', '\t'});
        pos += nl + 1;
        if (line.len == 0 or line[0] == '#') continue;
        if (is_system) {
            if (std.mem.indexOfScalar(u8, line, '=')) |_| continue;
        }

        var field_start: [5]usize = undefined;
        var field_end: [5]usize = undefined;
        var fpos: usize = 0;
        var fi: usize = 0;
        while (fi < 5 and fpos < line.len) {
            while (fpos < line.len and (line[fpos] == ' ' or line[fpos] == '\t')) : (fpos += 1) {}
            if (fpos >= line.len) break;
            field_start[fi] = fpos;
            while (fpos < line.len and line[fpos] != ' ' and line[fpos] != '\t') : (fpos += 1) {}
            field_end[fi] = fpos;
            fi += 1;
        }
        if (fi < 5) continue;

        if (!fieldMatches(line[field_start[0]..field_end[0]], current_min)) continue;
        if (!fieldMatches(line[field_start[1]..field_end[1]], current_hr)) continue;
        if (!fieldMatches(line[field_start[2]..field_end[2]], current_day)) continue;
        if (!fieldMatches(line[field_start[3]..field_end[3]], current_mon)) continue;
        if (!fieldMatches(line[field_start[4]..field_end[4]], current_wk)) continue;

        var cmd_start = fpos;
        if (is_system) {
            while (cmd_start < line.len and (line[cmd_start] == ' ' or line[cmd_start] == '\t')) : (cmd_start += 1) {}
            while (cmd_start < line.len and line[cmd_start] != ' ' and line[cmd_start] != '\t') : (cmd_start += 1) {}
        }
        while (cmd_start < line.len and (line[cmd_start] == ' ' or line[cmd_start] == '\t')) : (cmd_start += 1) {}
        if (cmd_start >= line.len) continue;
        const cmd = line[cmd_start..];

        var cmd_buf: [4096:0]u8 = undefined;
        if (cmd.len >= cmd_buf.len) continue;
        @memcpy(cmd_buf[0..cmd.len], cmd);
        cmd_buf[cmd.len] = 0;
        _ = core.c.system(cmd_buf[0..cmd.len :0].ptr);
    }
}

fn processDir(dir_path: []const u8, current_min: u32, current_hr: u32, current_day: u32, current_mon: u32, current_wk: u32) void {
    var zpath: [4096:0]u8 = undefined;
    if (dir_path.len >= zpath.len) return;
    @memcpy(zpath[0..dir_path.len], dir_path);
    zpath[dir_path.len] = 0;
    const dir = core.c.opendir(zpath[0..dir_path.len :0].ptr) orelse return;
    defer _ = core.c.closedir(dir);

    while (true) {
        const entry = core.c.readdir(dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (name.len == 0 or name[0] == '.') continue;

        var file_path_buf: [4096]u8 = undefined;
        const file_path = std.fmt.bufPrint(&file_path_buf, "{s}/{s}", .{ dir_path, name }) catch continue;
        processFile(file_path, false, current_min, current_hr, current_day, current_mon, current_wk);
    }
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-f")) {
        } else if (std.mem.eql(u8, args[i], "-l") and i + 1 < args.len) {
            i += 1;
        } else {
            return core.die(1, "usage: crond [-f] [-l N]\n", .{});
        }
        i += 1;
    }

    const t = core.c.time(null);
    const tm = core.c.localtime(&t);
    if (tm == null) return 1;
    const current_min: u32 = @intCast(tm.*.tm_min);
    const current_hr: u32 = @intCast(tm.*.tm_hour);
    const current_day: u32 = @intCast(tm.*.tm_mday);
    const current_mon: u32 = @intCast(tm.*.tm_mon + 1);
    const current_wk: u32 = @intCast(tm.*.tm_wday);

    processFile("/etc/crontab", true, current_min, current_hr, current_day, current_mon, current_wk);
    processDir("/var/spool/cron/crontabs", current_min, current_hr, current_day, current_mon, current_wk);

    return 0;
}
