const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "comm", .main = main };
pub fn main(args: [][]const u8) u8 {
    var suppress = [3]bool{ false, false, false };
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (args[i].len == 1) break;
        for (args[i][1..]) |c| {
            switch (c) {
                '1' => suppress[0] = true,
                '2' => suppress[1] = true,
                '3' => suppress[2] = true,
                else => return core.die(1, "comm: unknown flag '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    const files = args[i..];
    if (files.len < 2) return core.die(1, "comm: need two files\n", .{});
    var fds: [2]c_int = undefined;
    for (0..2) |j| {
        if (std.mem.eql(u8, files[j], "-")) {
            fds[j] = 0;
        } else {
            fds[j] = core.openReadName(files[j]) orelse return core.die(1, "comm: cannot open '{s}'\n", .{files[j]});
        }
    }
    defer {
        for (0..2) |j| {
            if (fds[j] > 0) _ = core.c.close(fds[j]);
        }
    }
    var r1 = core.LineReader.init(fds[0]);
    var r2 = core.LineReader.init(fds[1]);
    var l1 = r1.next();
    var l2 = r2.next();
    while (l1 != null or l2 != null) {
        if (l1 != null and l2 != null) {
            const cmp = std.mem.order(u8, l1.?, l2.?);
            if (cmp == .eq) {
                if (!suppress[2]) { core.writeAll(1, "\t\t"); core.writeAll(1, l1.?); }
                core.writeAll(1, "\n");
                l1 = r1.next();
                l2 = r2.next();
            } else if (cmp == .lt) {
                if (!suppress[0]) core.writeAll(1, l1.?);
                core.writeAll(1, "\n");
                l1 = r1.next();
            } else {
                if (!suppress[1]) { core.writeAll(1, "\t"); core.writeAll(1, l2.?); }
                core.writeAll(1, "\n");
                l2 = r2.next();
            }
        } else if (l1) |line| {
            if (!suppress[0]) core.writeAll(1, line);
            core.writeAll(1, "\n");
            l1 = r1.next();
        } else if (l2) |line| {
            if (!suppress[1]) { core.writeAll(1, "\t"); core.writeAll(1, line); }
            core.writeAll(1, "\n");
            l2 = r2.next();
        }
    }
    return 0;
}
