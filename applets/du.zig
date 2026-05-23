const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "du", .main = main };

fn formatSize(buf: []u8, size: u64, human: bool) []const u8 {
    if (!human) return std.fmt.bufPrint(buf, "{d}", .{size}) catch "";
    const units = [_][]const u8{ "B", "K", "M", "G", "T" };
    var s: f64 = @floatFromInt(size);
    var unit_idx: usize = 0;
    while (s >= 1024 and unit_idx < units.len - 1) {
        s /= 1024;
        unit_idx += 1;
    }
    if (unit_idx == 0) return std.fmt.bufPrint(buf, "{d}{s}", .{ size, units[unit_idx] }) catch "";
    return std.fmt.bufPrint(buf, "{d:.1}{s}", .{ s, units[unit_idx] }) catch "";
}

fn duDir(path: [:0]const u8) u64 {
    var total: u64 = 0;
    const d = core.c.opendir(path.ptr) orelse return 0;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        var sub_buf: [4096:0]u8 = undefined;
        if (path.len + 1 + name.len >= sub_buf.len) continue;
        @memcpy(sub_buf[0..path.len], path);
        sub_buf[path.len] = '/';
        @memcpy(sub_buf[path.len + 1 .. path.len + 1 + name.len], name);
        sub_buf[path.len + 1 + name.len] = 0;
        const sub_path = sub_buf[0..path.len + 1 + name.len :0];

        var st: core.c.struct_stat = undefined;
        if (core.c.stat(sub_path.ptr, &st) != 0) continue;

        if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
            total += duDir(sub_path);
        } else {
            total += @as(u64, @intCast(st.st_blocks * 512));
        }
    }
    return total;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var human = false;
    var bytes = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                's' => {},
                'h' => human = true,
                'b' => bytes = true,
                else => return core.die(1, "du: unknown flag '{c}'\n", .{c}),
            }
        }
        i += 1;
    }

    const paths = if (i >= args.len) &[_][]const u8{"."} else args[i..];
    var rc: u8 = 0;

    for (paths) |p| {
        var z_buf: [4096:0]u8 = undefined;
        if (p.len >= z_buf.len) { rc = 1; continue; }
        @memcpy(z_buf[0..p.len], p);
        z_buf[p.len] = 0;
        const path_z = z_buf[0..p.len :0];

        var st: core.c.struct_stat = undefined;
        if (core.c.stat(path_z.ptr, &st) != 0) {
            core.eprint("du: cannot stat '{s}'\n", .{p});
            rc = 1;
            continue;
        }

        const size = if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR)
            duDir(path_z)
        else
            @as(u64, @intCast(st.st_blocks * 512));

        var size_buf: [64]u8 = undefined;
        const display = if (bytes)
            std.fmt.bufPrint(&size_buf, "{d}", .{size}) catch "0"
        else
            formatSize(&size_buf, size, human);

        var line_buf: [4096 + 64]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{s}\t{s}\n", .{ display, p }) catch continue;
        core.writeAll(1, line);
    }

    return rc;
}
