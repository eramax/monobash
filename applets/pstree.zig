const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "pstree", .main = main };

const alloc = std.heap.page_allocator;
const ProcInfo = struct {
    pid: usize,
    ppid: usize,
    name: []u8,
    uid: u32,
};

fn readField(data: []const u8, field: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < data.len) {
        const nl = std.mem.indexOfScalar(u8, data[i..], '\n') orelse data.len;
        const line = data[i .. i + nl];
        i += nl + 1;
        if (std.mem.startsWith(u8, line, field)) {
            return std.mem.trim(u8, line[field.len..], " \t");
        }
    }
    return null;
}

fn readProcInfo(pid: usize) ?ProcInfo {
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/status", .{pid}) catch return null;
    var z_buf: [256:0]u8 = undefined;
    if (path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(&z_buf, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 4096) catch return null;
    defer alloc.free(data);

    const name_raw = readField(data, "Name:") orelse return null;
    const pid_str = readField(data, "Pid:") orelse return null;
    const ppid_str = readField(data, "PPid:") orelse return null;
    const uid_str = readField(data, "Uid:") orelse return null;

    const name = alloc.dupe(u8, name_raw) catch return null;
    const my_pid = std.fmt.parseUnsigned(usize, pid_str, 10) catch return null;
    const my_ppid = std.fmt.parseUnsigned(usize, ppid_str, 10) catch return null;
    var uid_it = std.mem.tokenizeScalar(u8, uid_str, ' ');
    const my_uid = std.fmt.parseUnsigned(u32, uid_it.next() orelse return null, 10) catch return null;

    return ProcInfo{ .pid = my_pid, .ppid = my_ppid, .name = name, .uid = my_uid };
}

fn printTree(procs: []const ProcInfo, parent_pid: usize, depth: usize, opt_pid: bool, opt_uid: bool, seen_uids: []u32) void {
    var children: std.ArrayListAligned(usize, null) = .empty;

    for (procs, 0..) |p, idx| {
        if (p.ppid == parent_pid) {
            children.append(alloc, idx) catch {};
        }
    }

    for (children.items, 0..) |idx, ci| {
        const p = procs[idx];
        const is_last = ci == children.items.len - 1;

        var pref: [256]u8 = undefined;
        var pref_pos: usize = 0;
        var d: usize = 0;
        while (d < depth) : (d += 1) {
            const indent: []const u8 = if (seen_uids[d] > 0 and seen_uids[d] != p.uid)
                "    "
            else if (d == depth - 1 and is_last)
                "    "
            else
                "\xE2\x94\x82   ";
            @memcpy(pref[pref_pos..][0..4], indent[0..4]);
            pref_pos += 4;
        }

        const branch: []const u8 = if (is_last) "\xE2\x94\x94\xE2\x94\x80\xE2\x94\x80" else "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80";
        @memcpy(pref[pref_pos..][0..4], branch[0..4]);
        pref_pos += 4;

        var buf: [512]u8 = undefined;
        const line = if (opt_pid)
            std.fmt.bufPrint(&buf, "{s}{s}({d})\n", .{ pref[0..pref_pos], p.name, p.pid }) catch continue
        else
            std.fmt.bufPrint(&buf, "{s}{s}\n", .{ pref[0..pref_pos], p.name }) catch continue;
        core.writeAll(1, line);

        if (opt_uid) {
            seen_uids[depth + 1] = 0;
        }

        printTree(procs, p.pid, depth + 1, opt_pid, opt_uid, seen_uids);
    }
}

pub fn main(args: [][]const u8) u8 {
    var opt_pid = false;
    var opt_uid = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-p")) opt_pid = true;
        if (std.mem.eql(u8, arg, "-u")) opt_uid = true;
    }

    var procs: std.ArrayListAligned(ProcInfo, null) = .empty;

    const proc_dir = core.c.opendir("/proc");
    if (proc_dir == null) return 1;
    defer _ = core.c.closedir(proc_dir);

    while (true) {
        const entry = core.c.readdir(proc_dir) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        const pid = std.fmt.parseUnsigned(usize, name, 10) catch continue;

        if (readProcInfo(pid)) |info| {
            procs.append(alloc, info) catch {
                alloc.free(info.name);
            };
        }
    }

    var seen_uids: [256]u32 = @splat(0);
    printTree(procs.items, 0, 0, opt_pid, opt_uid, &seen_uids);

    return 0;
}
