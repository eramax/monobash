const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "cmp", .main = main };
pub fn main(args: [][]const u8) u8 {
    var opt_l = false;
    var opt_s = false;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| switch (c) {
            'l' => opt_l = true,
            's' => opt_s = true,
            else => return core.die(2, "cmp: unknown flag '-{c}'\n", .{c}),
        };
        i += 1;
    }
    if (i + 2 > args.len) return core.die(2, "cmp: missing file arguments\n", .{});
    const alloc = std.heap.page_allocator;
    const buf1 = readFile(args[i], alloc) orelse return 2;
    defer alloc.free(buf1);
    const buf2 = readFile(args[i + 1], alloc) orelse return 2;
    defer alloc.free(buf2);
    const min_len = @min(buf1.len, buf2.len);
    var differ = false;
    var pos: usize = 0;
    while (pos < min_len) {
        if (buf1[pos] != buf2[pos]) {
            differ = true;
            if (opt_l) {
                var nbuf: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&nbuf, "{d} {o} {o}\n", .{ pos + 1, buf1[pos], buf2[pos] }) catch "";
                core.writeAll(1, s);
            }
        }
        pos += 1;
    }
    if (buf1.len != buf2.len) differ = true;
    if (differ) {
        if (!opt_s and !opt_l) core.eprint("cmp: {s} {s} differ: byte {d}\n", .{ args[i], args[i + 1], pos + 1 });
        return 1;
    }
    return 0;
}
fn readFile(name: []const u8, alloc: std.mem.Allocator) ?[]u8 {
    var fbuf: [4096:0]u8 = undefined;
    if (name.len >= fbuf.len) return null;
    @memcpy(fbuf[0..name.len], name);
    fbuf[name.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 1024 * 1024) catch null;
}
