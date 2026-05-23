const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "tree", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var dirs_list = std.ArrayListAligned([]const u8, null).empty;
    defer dirs_list.deinit(std.heap.page_allocator);
    while (i < args.len) {
        dirs_list.append(std.heap.page_allocator, args[i]) catch {};
        i += 1;
    }
    if (dirs_list.items.len == 0) {
        dirs_list.append(std.heap.page_allocator, ".") catch {};
    }
    var total_dirs: usize = 0;
    var total_files: usize = 0;
    for (dirs_list.items) |dir| {
        var counts: [2]usize = .{ 0, 0 };
        treePrint(&counts, dir, dir, "");
        total_dirs += counts[0];
        total_files += counts[1];
    }
    var sum_buf: [128]u8 = undefined;
    const sum_str = std.fmt.bufPrint(&sum_buf, "\n{d} directories, {d} files\n", .{ total_dirs, total_files }) catch "\n0 directories, 0 files\n";
    core.writeAll(1, sum_str);
    return 0;
}

fn treePrint(counts: *[2]usize, display_name: []const u8, full_path: []const u8, prefix: []const u8) void {
    var zdir: [4096:0]u8 = undefined;
    if (full_path.len >= zdir.len) return;
    @memcpy(zdir[0..full_path.len], full_path);
    zdir[full_path.len] = 0;

    const dir_obj = core.c.opendir(&zdir);
    if (dir_obj == null) {
        core.writeAll(1, display_name);
        core.writeAll(1, " [error opening dir]\n");
        return;
    }
    defer _ = core.c.closedir(dir_obj);

    const alloc = std.heap.page_allocator;
    var names = std.ArrayListAligned([]u8, null).empty;
    defer {
        for (names.items) |n| alloc.free(n);
        names.deinit(alloc);
    }

    while (true) {
        const entry = core.c.readdir(dir_obj) orelse break;
        const de = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&de.d_name)), 0);
        if (name[0] == '.') continue;
        const dup = alloc.dupe(u8, name) catch continue;
        names.append(alloc, dup) catch { alloc.free(dup); continue; };
    }

    core.writeAll(1, display_name);
    core.writeAll(1, "\n");

    if (names.items.len == 0) return;

    std.mem.sortUnstable([]u8, names.items, {}, struct {
        fn less(_: void, a: []u8, b: []u8) bool { return std.mem.lessThan(u8, a, b); }
    }.less);

    for (names.items, 0..) |name, idx| {
        const last = idx == names.items.len - 1;

        var path_buf: [4096:0]u8 = undefined;
        var path_len: usize = 0;
        if (full_path.len + 1 + name.len < path_buf.len) {
            @memcpy(path_buf[0..full_path.len], full_path);
            path_len = full_path.len;
            if (path_len > 0 and path_buf[path_len - 1] != '/') {
                path_buf[path_len] = '/';
                path_len += 1;
            }
            @memcpy(path_buf[path_len..][0..name.len], name);
            path_len += name.len;
            path_buf[path_len] = 0;
        } else continue;
        const child_path: []const u8 = path_buf[0..path_len];

        var st: core.c.struct_stat = undefined;
        const st_rc = core.c.lstat(&path_buf, &st);

        core.writeAll(1, prefix);
        core.writeAll(1, if (last) "└── " else "├── ");

        if (st_rc == 0 and (st.st_mode & core.c.S_IFMT) == core.c.S_IFLNK) {
            var linkbuf: [4096]u8 = undefined;
            const ln = core.c.readlink(&path_buf, &linkbuf, linkbuf.len);
            core.writeAll(1, name);
            if (ln > 0) {
                core.writeAll(1, " -> ");
                core.writeAll(1, linkbuf[0..@intCast(ln)]);
            }
            core.writeAll(1, "\n");
            counts[1] += 1;
        } else if (st_rc == 0 and (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
            var sub_buf: [4096]u8 = undefined;
            const sub_prefix = std.fmt.bufPrint(&sub_buf, "{s}{s}", .{ prefix, if (last) "    " else "│   " }) catch "";
            treePrint(counts, name, child_path, sub_prefix);
            counts[0] += 1;
        } else {
            core.writeAll(1, name);
            core.writeAll(1, "\n");
            counts[1] += 1;
        }
    }
}
