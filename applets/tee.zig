const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tee", .main = main };

pub fn main(args: [][]const u8) u8 {
    var append = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'a' => append = true,
                else => return core.die(1, "tee: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];

    const data = core.readAll(std.heap.page_allocator, 0, 1024 * 1024) catch return 1;
    defer std.heap.page_allocator.free(data);

    core.writeAll(1, data);

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("tee: {s}: path too long\n", .{f});
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;

        const flags = if (append) core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND else core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC;
        const fd = core.c.open(&fbuf, flags, @as(c_uint, 0o666));
        if (fd < 0) {
            core.eprint("tee: {s}: Cannot open\n", .{f});
            continue;
        }
        defer _ = core.c.close(fd);
        core.writeAll(fd, data);
    }

    return 0;
}
