const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "iptunnel", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const fd = core.c.opendir("/sys/class/net".ptr);
    if (fd == null) return 1;
    defer _ = core.c.closedir(fd);

    while (true) {
        const dent = core.c.readdir(fd) orelse break;
        const name = std.mem.sliceTo(@as([*]u8, @ptrCast(&dent.*.d_name)), 0);
        if (name.len == 0 or (name.len == 1 and name[0] == '.') or (name.len == 2 and name[0] == '.' and name[1] == '.')) continue;

        const type_path = std.fmt.allocPrint(alloc, "/sys/class/net/{s}/type", .{name}) catch continue;
        defer alloc.free(type_path);
        const type_s = readLine(alloc, type_path) orelse continue;
        defer alloc.free(type_s);
        const iftype = std.fmt.parseInt(u32, type_s, 10) catch 0;

        if (iftype == 768 or iftype == 769 or iftype == 801) {
            var out: [128]u8 = undefined;
            const o = std.fmt.bufPrint(&out, "{s}: tunnel\n", .{name}) catch continue;
            core.writeAll(1, o);
        }
    }
    return 0;
}

fn readLine(alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    var p: [4096:0]u8 = undefined;
    if (path.len >= p.len) return null;
    @memcpy(p[0..path.len], path);
    p[path.len] = 0;
    const f = core.c.open(&p, core.c.O_RDONLY);
    if (f < 0) return null;
    defer _ = core.c.close(f);
    const data = core.readAll(alloc, f, 4096) catch return null;
    defer alloc.free(data);
    var i: usize = 0;
    while (i < data.len and data[i] != '\n' and data[i] != '\r') i += 1;
    return alloc.dupe(u8, data[0..i]) catch null;
}
