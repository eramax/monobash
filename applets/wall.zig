const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "wall", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const msg = if (args.len > 1) blk: {
        break :blk std.mem.join(alloc, " ", args[1..]) catch return 1;
    } else blk: {
        const data = core.readAll(std.heap.page_allocator, 0, 65536) catch return 1;
        break :blk data;
    };
    defer if (args.len > 1) alloc.free(msg);
    const d = core.c.opendir("/dev/pts");
    if (d == null) return core.die(1, "wall: cannot open /dev/pts\n", .{});
    defer _ = core.c.closedir(d);
    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);
        if (name.len == 0) continue;
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        var is_num = true;
        for (name) |ch| {
            if (ch < '0' or ch > '9') { is_num = false; break; }
        }
        if (!is_num) continue;
        var path: [64]u8 = undefined;
        const sub = std.fmt.bufPrint(&path, "/dev/pts/{s}", .{name}) catch continue;
        var buf: [4096:0]u8 = undefined;
        if (sub.len >= buf.len) continue;
        @memcpy(buf[0..sub.len], sub);
        buf[sub.len] = 0;
        const fd = core.c.open(&buf, core.c.O_WRONLY);
        if (fd < 0) continue;
        core.writeAll(fd, "Message from sysadmin:\n");
        core.writeAll(fd, msg);
        core.writeAll(fd, "\n");
        _ = core.c.close(fd);
    }
    return 0;
}
