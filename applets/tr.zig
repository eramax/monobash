const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tr", .main = main };

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
                else => return core.die(1, "tr: unknown flag '{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const set1 = if (i < args.len) args[i] else return core.die(1, "tr: missing SET1\n", .{});
    i += 1;
    const set2 = if (i < args.len) args[i] else "";

    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);

    var buf: [1024 * 1024]u8 = undefined;
    var pos: usize = 0;
    var prev_char: u8 = 0;

    for (data) |ch| {
        if (do_delete) {
            if (charInSet(ch, set1)) continue;
        }

        if (do_squeeze) {
            if (charInSet(ch, set1) and ch == prev_char) continue;
        }

        var out = ch;

        if (!do_delete and set2.len > 0) {
            const idx = charIndex(ch, set1);
            if (idx < set2.len) {
                out = set2[idx];
            } else if (idx != std.math.maxInt(usize) and set2.len > 0) {
                out = set2[set2.len - 1];
            }
        }

        buf[pos] = out;
        prev_char = out;
        pos += 1;
    }

    core.writeAll(1, buf[0..pos]);
    return 0;
}

fn charInSet(ch: u8, set: []const u8) bool {
    var j: usize = 0;
    while (j < set.len) {
        if (j + 2 < set.len and set[j + 1] == '-') {
            if (ch >= set[j] and ch <= set[j + 2]) return true;
            j += 3;
        } else {
            if (set[j] == ch) return true;
            j += 1;
        }
    }
    return false;
}

fn charIndex(ch: u8, set: []const u8) usize {
    var j: usize = 0;
    var idx: usize = 0;
    while (j < set.len) {
        if (j + 2 < set.len and set[j + 1] == '-') {
            if (ch >= set[j] and ch <= set[j + 2]) {
                return idx + (ch - set[j]);
            }
            idx += (set[j + 2] - set[j]) + 1;
            j += 3;
        } else {
            if (set[j] == ch) return idx;
            idx += 1;
            j += 1;
        }
    }
    return std.math.maxInt(usize);
}
