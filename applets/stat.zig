const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "stat", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    var rc: u8 = 0;
    for (args[1..]) |path| {
        var z_buf: [4096:0]u8 = undefined;
        if (path.len >= z_buf.len) { rc = 1; continue; }
        @memcpy(z_buf[0..path.len], path);
        z_buf[path.len] = 0;
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(z_buf[0..path.len :0].ptr, &st) != 0) {
            core.eprint("stat: cannot stat '{s}'\n", .{path});
            rc = 1;
            continue;
        }
        var buf: [2048]u8 = undefined;
        const out = std.fmt.bufPrint(&buf,
            \\  File: {s}
            \\  Size: {d}        Blocks: {d}       IO Block: {d}
            \\Device: {x}h/{d}d    Inode: {d}     Links: {d}
            \\Access: ({o:>4})  Uid: {d}     Gid: {d}
            \\Modify: {d}
            \\Change: {d}
            \\ Birth: {d}
            \\
        , .{
            path,
            @as(u64, @intCast(st.st_size)),
            @as(u64, @intCast(st.st_blocks)),
            @as(u64, @intCast(st.st_blksize)),
            @as(u64, @intCast(st.st_dev)),
            @as(u64, @intCast(st.st_dev)),
            @as(u64, @intCast(st.st_ino)),
            @as(u64, @intCast(st.st_nlink)),
            @as(u32, @intCast(st.st_mode)),
            @as(u32, @intCast(st.st_uid)),
            @as(u32, @intCast(st.st_gid)),
            @as(i64, @intCast(st.st_mtim.tv_sec)),
            @as(i64, @intCast(st.st_ctim.tv_sec)),
            @as(i64, @intCast(st.st_atim.tv_sec)),
        }) catch "";
        core.writeAll(1, out);
    }
    return rc;
}
