const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "paste", .main = main };
pub fn main(args: [][]const u8) u8 {
    var delim: u8 = '\t';
    var i: usize = 1;
    if (i < args.len and std.mem.eql(u8, args[i], "-d")) {
        i += 1;
        if (i >= args.len) return core.die(1, "paste: missing delimiter after -d\n", .{});
        delim = if (args[i].len > 0) args[i][0] else '\t';
        i += 1;
    }
    const files = args[i..];
    if (files.len < 2) return core.die(1, "paste: need at least two files\n", .{});
    var readers: [2]core.LineReader = undefined;
    var fds: [2]c_int = undefined;
    for (0..2) |j| {
        fds[j] = core.openReadName(files[j]) orelse return core.die(1, "paste: cannot open '{s}'\n", .{files[j]});
        readers[j] = core.LineReader.init(fds[j]);
    }
    defer { for (fds) |fd| _ = core.c.close(fd); }
    while (true) {
        const line0 = readers[0].next();
        const line1 = readers[1].next();
        if (line0 == null and line1 == null) break;
        if (line0) |l| core.writeAll(1, l);
        core.writeAll(1, &[_]u8{delim});
        if (line1) |l| core.writeAll(1, l);
        core.writeAll(1, "\n");
    }
    return 0;
}
