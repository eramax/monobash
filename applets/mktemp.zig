const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mktemp", .main = main };

var rng_state: u64 = 0;

fn randomChar() u8 {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    if (rng_state == 0) {
        rng_state = @as(u64, @intCast(core.c.getpid())) +% @intFromPtr(&rng_state);
    }
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    return chars[@intCast(rng_state % chars.len)];
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var is_dir = false;
    var dry_run = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'd' => is_dir = true,
                'u' => dry_run = true,
                else => return core.die(1, "mktemp: invalid option: -{c}\n", .{c}),
            }
        }
        i += 1;
    }
    const template = if (i < args.len) args[i] else "tmp.XXXXXXXXXX";
    var buf: [4096:0]u8 = undefined;
    if (template.len >= buf.len) return 1;
    @memcpy(buf[0..template.len], template);
    buf[template.len] = 0;
    var count: usize = 0;
    for (buf[0..template.len]) |ch| {
        if (ch == 'X') count += 1;
    }
    if (count == 0) return core.die(1, "mktemp: template must contain at least one X\n", .{});
    var max_attempts: u32 = 100;
    while (max_attempts > 0) {
        max_attempts -= 1;
        var j: usize = 0;
        while (j < template.len) {
            if (buf[j] == 'X') buf[j] = randomChar();
            j += 1;
        }
        buf[template.len] = 0;
        if (dry_run) {
            core.writeAll(1, buf[0..template.len]);
            core.writeAll(1, "\n");
            return 0;
        }
        var fd: c_int = undefined;
        if (is_dir) {
            if (core.c.mkdir(&buf, 0o700) == 0) {
                core.writeAll(1, buf[0..template.len]);
                core.writeAll(1, "\n");
                return 0;
            }
        } else {
            fd = core.c.mkstemp(&buf);
            if (fd >= 0) {
                _ = core.c.close(fd);
                core.writeAll(1, buf[0..template.len]);
                core.writeAll(1, "\n");
                return 0;
            }
        }
    }
    return core.die(1, "mktemp: cannot create temp file from template '{s}'\n", .{template});
}
