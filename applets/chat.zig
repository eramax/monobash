const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "chat", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: chat EXPECT SEND [EXPECT SEND...]\n", .{});

    const timeout_s: i64 = 5;

    var tv: core.c.struct_timeval = std.mem.zeroes(core.c.struct_timeval);
    tv.tv_sec = timeout_s;
    _ = core.c.setsockopt(0, core.c.SOL_SOCKET, core.c.SO_RCVTIMEO, &tv, @sizeOf(@TypeOf(tv)));

    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return core.die(1, "chat: missing send string\n", .{});

        const expect = args[i];
        const send = args[i + 1];

        if (expect.len > 0) {
            var buf: [4096]u8 = undefined;
            var pos: usize = 0;
            var matched = false;

            const deadline = if (timeout_s > 0) core.c.time(null) + timeout_s else 0;

            while (!matched) {
                if (pos >= buf.len) break;
                const n = core.c.read(0, &buf[pos], 1);
                if (n <= 0) break;

                if (buf[pos] == expect[0]) {
                    const remaining = buf.len - pos;
                    const to_check = @min(remaining, expect.len);
                    @memcpy(buf[pos..][0..to_check], buf[pos..][0..to_check]);
                    var all_match = true;
                    for (0..expect.len) |j| {
                        if (buf[pos + j] != expect[j]) { all_match = false; break; }
                    }
                    if (all_match) { matched = true; break; }
                }
                pos += 1;

                if (deadline > 0 and core.c.time(null) >= deadline) break;
            }

            if (!matched) return core.die(1, "chat: expected '{s}' not found\n", .{expect});
        }

        if (send.len > 0) {
            _ = core.c.write(1, send.ptr, send.len);
            _ = core.c.write(1, "\r", 1);
        }
    }

    return 0;
}
