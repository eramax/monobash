const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cp", .main = main };

const SymPolicy = enum { follow_args, follow_all, no_follow };

const Flags = struct {
    recursive: bool = false,
    force: bool = false,
    interactive: bool = false,
    verbose: bool = false,
    sym_policy: SymPolicy = .follow_args,
    hardlink: bool = false,
    symlink: bool = false,
    parents: bool = false,
};

fn copyFile(src: [:0]const u8, dst: [:0]const u8) u8 {
    const fd_src = core.c.open(src.ptr, core.c.O_RDONLY);
    if (fd_src < 0) return 1;
    defer _ = core.c.close(fd_src);
    const fd_dst = core.c.open(dst.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o666));
    if (fd_dst < 0) return 1;
    defer _ = core.c.close(fd_dst);
    while (true) {
        const data = core.readAll(std.heap.page_allocator, fd_src, 65536) catch return 1;
        defer std.heap.page_allocator.free(data);
        if (data.len == 0) return 0;
        core.writeAll(fd_dst, data);
    }
}

fn copySymlink(src: [:0]const u8, dst: [:0]const u8) u8 {
    var buf: [4096]u8 = undefined;
    const n = core.c.readlink(src.ptr, &buf, buf.len);
    if (n < 0) return 1;
    const target = buf[0..@intCast(n)];
    var dbuf: [4096:0]u8 = undefined;
    if (target.len >= dbuf.len) return 1;
    @memcpy(dbuf[0..target.len], target);
    dbuf[target.len] = 0;
    if (core.c.symlink(dbuf[0..target.len :0].ptr, dst.ptr) < 0) return 1;
    return 0;
}

fn copyDir(fl: *const Flags, src: [:0]const u8, dst: [:0]const u8) u8 {
    if (core.c.mkdir(dst.ptr, 0o755) != 0) {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(dst.ptr, &st) != 0) return 1;
        if ((st.st_mode & core.c.S_IFMT) != core.c.S_IFDIR) return 1;
    }
    const d = core.c.opendir(src.ptr) orelse return 1;
    defer _ = core.c.closedir(d);
    var sub_src: [4096:0]u8 = undefined;
    var sub_dst: [4096:0]u8 = undefined;
    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (src.len + 1 + name.len >= sub_src.len) continue;
        if (dst.len + 1 + name.len >= sub_dst.len) continue;
        @memcpy(sub_src[0..src.len], src);
        sub_src[src.len] = '/';
        @memcpy(sub_src[src.len + 1 .. src.len + 1 + name.len], name);
        sub_src[src.len + 1 + name.len] = 0;
        @memcpy(sub_dst[0..dst.len], dst);
        sub_dst[dst.len] = '/';
        @memcpy(sub_dst[dst.len + 1 .. dst.len + 1 + name.len], name);
        sub_dst[dst.len + 1 + name.len] = 0;
        const full_src = sub_src[0..src.len + 1 + name.len :0];
        const full_dst = sub_dst[0..dst.len + 1 + name.len :0];
        if (copyOne(fl, full_src, full_dst, false) != 0) return 1;
    }
    return 0;
}

fn copyOne(fl: *const Flags, src: [:0]const u8, dst: [:0]const u8, is_cmdline: bool) u8 {
    // Check if source is a symlink
    var lst: core.c.struct_stat = undefined;
    const is_symlink = core.c.lstat(src.ptr, &lst) == 0 and (lst.st_mode & core.c.S_IFMT) == core.c.S_IFLNK;

    // Determine whether to follow
    const follow = is_symlink and (fl.sym_policy == .follow_all or (fl.sym_policy == .follow_args and is_cmdline));

    if (is_symlink and !follow) {
        // Copy the symlink itself
        if (fl.hardlink) {
            var buf: [4096]u8 = undefined;
            const n = core.c.readlink(src.ptr, &buf, buf.len);
            if (n < 0) return 1;
            const target = buf[0..@intCast(n)];
            var dbuf: [4096:0]u8 = undefined;
            if (target.len >= dbuf.len) return 1;
            @memcpy(dbuf[0..target.len], target);
            dbuf[target.len] = 0;
            if (core.c.link(dbuf[0..target.len :0].ptr, dst.ptr) < 0) return 1;
            return 0;
        }
        if (fl.symlink) {
            return copySymlink(src, dst);
        }
        return copySymlink(src, dst);
    }

    // Get target info (following symlink if applicable)
    var st: core.c.struct_stat = undefined;
    if (follow) {
        if (core.c.stat(src.ptr, &st) != 0) return 1;
    } else {
        if (core.c.lstat(src.ptr, &st) != 0) return 1;
    }

    if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
        if (!fl.recursive) {
            core.eprint("cp: omitting directory '{s}'\n", .{src});
            return 1;
        }
        return copyDir(fl, src, dst);
    }

    // Regular file
    if (fl.hardlink) {
        if (core.c.link(src.ptr, dst.ptr) < 0) return 1;
        return 0;
    }
    if (fl.symlink) {
        var buf: [4096]u8 = undefined;
        const n = core.c.readlink(src.ptr, &buf, buf.len);
        if (n < 0) return 1;
        const target = buf[0..@intCast(n)];
        var dbuf: [4096:0]u8 = undefined;
        if (target.len >= dbuf.len) return 1;
        @memcpy(dbuf[0..target.len], target);
        dbuf[target.len] = 0;
        if (core.c.symlink(dbuf[0..target.len :0].ptr, dst.ptr) < 0) return 1;
        return 0;
    }

    return copyFile(src, dst);
}

pub fn main(args: [][]const u8) u8 {
    var fl = Flags{};
    var sym_set = false;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i], "--parents")) { fl.parents = true; i += 1; continue; }
        if (args[i].len > 2 and args[i][1] == '-') { i += 1; continue; } // skip unknown long opts
        for (args[i][1..]) |c| {
            switch (c) {
                'a' => { fl.recursive = true; fl.sym_policy = .no_follow; sym_set = true; },
                'r', 'R' => fl.recursive = true,
                'f' => fl.force = true,
                'i' => fl.interactive = true,
                'v' => fl.verbose = true,
                'd' => { fl.sym_policy = .no_follow; sym_set = true; },
                'P' => { fl.sym_policy = .no_follow; sym_set = true; },
                'H' => { fl.sym_policy = .follow_args; sym_set = true; },
                'L' => { fl.sym_policy = .follow_all; sym_set = true; },
                'l' => fl.hardlink = true,
                's' => fl.symlink = true,
                else => return 1,
            }
        }
        i += 1;
    }
    // Default: -R implies no_follow, otherwise follow_args
    if (!sym_set and fl.recursive) fl.sym_policy = .no_follow;
    if (i + 1 >= args.len) return 1;

    const src_names = args[i .. args.len - 1];
    const dst_name = args[args.len - 1];

    if (src_names.len == 0) return 1;

    // If destination is a directory, copy each source into it
    var dst_buf: [4096:0]u8 = undefined;
    if (dst_name.len >= dst_buf.len) return 1;
    @memcpy(dst_buf[0..dst_name.len], dst_name);
    dst_buf[dst_name.len] = 0;
    const dst_z = dst_buf[0..dst_name.len :0];
    var dst_st: core.c.struct_stat = undefined;
    const dst_is_dir = core.c.stat(dst_z.ptr, &dst_st) == 0 and (dst_st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR;

    var rc: u8 = 0;
    for (src_names) |src| {
        var s_buf: [4096:0]u8 = undefined;
        if (src.len >= s_buf.len) { rc = 1; continue; }
        @memcpy(s_buf[0..src.len], src);
        s_buf[src.len] = 0;
        const src_z = s_buf[0..src.len :0];

        if (fl.parents) {
            // --parents: Create intermediate directories
            var path_copy: [4096:0]u8 = undefined;
            if (dst_name.len + 1 + src.len >= path_copy.len) { rc = 1; continue; }
            @memcpy(path_copy[0..dst_name.len], dst_name);
            path_copy[dst_name.len] = '/';
            @memcpy(path_copy[dst_name.len + 1 .. dst_name.len + 1 + src.len], src);
            path_copy[dst_name.len + 1 + src.len] = 0;
            const full_dst_path = path_copy[0..dst_name.len + 1 + src.len :0];

            // Create intermediate dirs (all but the last component)
            const last_component_start = std.mem.lastIndexOfScalar(u8, src, '/') orelse 0;
            if (last_component_start > 0) {
                var seg: usize = 0;
                while (seg < last_component_start) {
                    var sl = seg;
                    while (sl < src.len and src[sl] != '/') sl += 1;
                    if (sl > seg) {
                        var mkpath: [4096:0]u8 = undefined;
                        if (dst_name.len + 1 + sl >= mkpath.len) { seg = sl + 1; continue; }
                        @memcpy(mkpath[0..dst_name.len], dst_name);
                        mkpath[dst_name.len] = '/';
                        @memcpy(mkpath[dst_name.len + 1 .. dst_name.len + 1 + sl], src[0..sl]);
                        mkpath[dst_name.len + 1 + sl] = 0;
                        _ = core.c.mkdir(mkpath[0..dst_name.len + 1 + sl :0].ptr, 0o755);
                    }
                    seg = sl + 1;
                }
            }
            const r = copyOne(&fl, src_z, full_dst_path, true);
            if (r > rc) rc = r;
        } else if (dst_is_dir) {
            // Copy into directory: src -> dst/basename(src)
            var path_buf: [4096:0]u8 = undefined;
            const base = std.fs.path.basename(src);
            if (dst_name.len + 1 + base.len >= path_buf.len) { rc = 1; continue; }
            @memcpy(path_buf[0..dst_name.len], dst_name);
            path_buf[dst_name.len] = '/';
            @memcpy(path_buf[dst_name.len + 1 .. dst_name.len + 1 + base.len], base);
            path_buf[dst_name.len + 1 + base.len] = 0;
            const pdst = path_buf[0..dst_name.len + 1 + base.len :0];

            if (fl.interactive) {
                var st: core.c.struct_stat = undefined;
                if (core.c.stat(pdst.ptr, &st) == 0) {
                    core.writeAll(1, "cp: overwrite '");
                    core.writeAll(1, pdst);
                    core.writeAll(1, "'? ");
                    var resp: [4]u8 = undefined;
                    const n = core.c.read(0, &resp, resp.len);
                    if (n <= 0 or (resp[0] != 'y' and resp[0] != 'Y')) continue;
                }
            }

            const r = copyOne(&fl, src_z, pdst, true);
            if (r > rc) rc = r;
        } else {
            // Single source to single destination (last arg)
            if (fl.interactive) {
                var st: core.c.struct_stat = undefined;
                if (core.c.stat(dst_z.ptr, &st) == 0) {
                    core.writeAll(1, "cp: overwrite '");
                    core.writeAll(1, dst_name);
                    core.writeAll(1, "'? ");
                    var resp: [4]u8 = undefined;
                    const n = core.c.read(0, &resp, resp.len);
                    if (n <= 0 or (resp[0] != 'y' and resp[0] != 'Y')) return 0;
                }
            }
            const r = copyOne(&fl, src_z, dst_z, true);
            return if (r > rc) r else rc;
        }
    }
    return rc;
}
