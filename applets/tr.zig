const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tr", .main = main };

fn expandSet(set: []const u8, buf: []u8) usize {
    var pos: usize = 0;
    var j: usize = 0;
    while (j < set.len and pos < buf.len) {
        if (j + 2 < set.len and set[j + 1] == '-') {
            const from = set[j];
            const to = set[j + 2];
            var c = from;
            while (c <= to and pos < buf.len) {
                buf[pos] = c;
                pos += 1;
                c += 1;
            }
            j += 3;
        } else {
            buf[pos] = set[j];
            pos += 1;
            j += 1;
        }
    }
    return pos;
}

pub fn main(args: [][]const u8) u8 {
    var do_delete = false;
    var do_squeeze = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'd' => do_delete = true,
                's' => do_squeeze = true,
                else => return core.die(1, "tr: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const set1_raw = if (i < args.len) args[i] else return core.die(1, "tr: missing SET1\n", .{});
    i += 1;
    const set2_raw = if (i < args.len) args[i] else "";

    var set1_buf: [256]u8 = undefined;
    var set2_buf: [256]u8 = undefined;
    const set1_len = expandSet(set1_raw, &set1_buf);
    const set2_len = expandSet(set2_raw, &set2_buf);
    const set1 = set1_buf[0..set1_len];
    const set2 = set2_buf[0..set2_len];

    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);

    var buf: [1024 * 1024]u8 = undefined;
    var pos: usize = 0;
    var prev_char: u8 = 0;

    for (data) |ch| {
        if (do_delete) {
            if (std.mem.indexOfScalar(u8, set1, ch) != null) continue;
        }

        if (do_squeeze) {
            if (std.mem.indexOfScalar(u8, set1, ch) != null and ch == prev_char) continue;
        }

        var out = ch;
        if (!do_delete and set2.len > 0) {
            if (std.mem.indexOfScalar(u8, set1, ch)) |idx| {
                if (idx < set2.len) {
                    out = set2[idx];
                } else {
                    out = set2[set2.len - 1];
                }
            }
        }

        buf[pos] = out;
        prev_char = out;
        pos += 1;
    }

    core.writeAll(1, buf[0..pos]);
    return 0;
}
