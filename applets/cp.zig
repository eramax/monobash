const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "cp", .main = main };

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

fn copyDir(src: [:0]const u8, dst: [:0]const u8, verbose: bool) u8 {
    if (core.c.mkdir(dst.ptr, 0o755) != 0) {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(dst.ptr, &st) != 0) return 1;
        if ((st.st_mode & core.c.S_IFMT) != core.c.S_IFDIR) return 1;
    } else if (verbose) {
        core.eprint("cp: created directory '{s}'\n", .{dst});
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
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(full_src.ptr, &st) == 0 and (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
            if (copyDir(full_src, full_dst, verbose) != 0) return 1;
        } else {
            if (verbose) core.eprint("cp: '{s}' -> '{s}'\n", .{full_src, full_dst});
            if (copyFile(full_src, full_dst) != 0) return 1;
        }
    }
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var recursive = false;
    var force = false;
    var interactive = false;
    var verbose = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'r', 'R' => recursive = true,
                'f' => force = true,
                'i' => interactive = true,
                'v' => verbose = true,
                else => return 1,
            }
        }
        i += 1;
    }
    if (i + 1 >= args.len) return 1;
    const src = args[i];
    const dst = args[i + 1];
    if (src.len == 0 or dst.len == 0) return 1;
    var src_buf: [4096:0]u8 = undefined;
    var dst_buf: [4096:0]u8 = undefined;
    if (src.len >= src_buf.len or dst.len >= dst_buf.len) return 1;
    @memcpy(src_buf[0..src.len], src);
    src_buf[src.len] = 0;
    @memcpy(dst_buf[0..dst.len], dst);
    dst_buf[dst.len] = 0;
    const src_z = src_buf[0..src.len :0];
    const dst_z = dst_buf[0..dst.len :0];
    const fd = core.c.open(dst_z.ptr, core.c.O_RDONLY);
    if (fd >= 0) {
        _ = core.c.close(fd);
        if (interactive) {
            core.writeAll(1, "overwrite '");
            core.writeAll(1, dst);
            core.writeAll(1, "'? ");
            var resp: [4]u8 = undefined;
            const n = core.c.read(0, &resp, resp.len);
            if (n <= 0 or (resp[0] != 'y' and resp[0] != 'Y')) return 0;
        }
    }
    var st: core.c.struct_stat = undefined;
    if (recursive and core.c.stat(src_z.ptr, &st) == 0 and (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) {
        return copyDir(src_z, dst_z, verbose);
    }
    if (verbose) core.eprint("cp: '{s}' -> '{s}'\n", .{src, dst});
    return copyFile(src_z, dst_z);
}
