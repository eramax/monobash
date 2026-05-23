const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mv", .main = main };

fn copyFile(src: [:0]const u8, dst: [:0]const u8) u8 {
    const fd_src = core.c.open(src.ptr, core.c.O_RDONLY);
    if (fd_src < 0) return 1;
    defer _ = core.c.close(fd_src);
    const fd_dst = core.c.open(dst.ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o666));
    if (fd_dst < 0) return 1;
    defer _ = core.c.close(fd_dst);
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = core.c.read(fd_src, &buf, buf.len);
        if (n <= 0) return if (n < 0) @as(u8, 1) else @as(u8, 0);
        var off: usize = 0;
        while (off < @as(usize, @intCast(n))) {
            const w = core.c.write(fd_dst, @as([*]u8, @ptrCast(&buf)) + off, @as(usize, @intCast(n)) - off);
            if (w < 0) return 1;
            off += @intCast(w);
        }
    }
}

fn moveFile(src: [:0]const u8, dst: [:0]const u8, force: bool, interactive: bool, verbose: bool) u8 {
    _ = force;
    const fd = core.c.open(dst.ptr, core.c.O_RDONLY);
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
    const rc = core.c.rename(src.ptr, dst.ptr);
    if (rc == 0) {
        if (verbose) core.eprint("mv: '{s}' -> '{s}'\n", .{src, dst});
        return 0;
    }
    if (copyFile(src, dst) != 0) return 1;
    _ = core.c.unlink(src.ptr);
    if (verbose) core.eprint("mv: '{s}' -> '{s}'\n", .{src, dst});
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var force = false;
    var interactive = false;
    var verbose = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
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
    return moveFile(src_buf[0..src.len :0], dst_buf[0..dst.len :0], force, interactive, verbose);
}
