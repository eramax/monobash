const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mesg", .main = main };

pub fn main(args: [][]const u8) u8 {
    const tty = core.c.ttyname(0);
    if (tty == null) return core.die(1, "mesg: not a terminal\n", .{});
    if (args.len < 2) {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(tty, &st) != 0) return 1;
        const writable = (st.st_mode & @as(c_uint, 0o022)) != 0;
        core.writeAll(1, if (writable) "is y\n" else "is n\n");
        return 0;
    }
    if (args[1].len == 0) return 1;
    const c = args[1][0];
    if (c == 'y' or c == 'Y') {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(tty, &st) != 0) return 1;
        const new_mode = st.st_mode | @as(c_uint, 0o022);
        if (core.c.chmod(tty, @as(c_uint, @intCast(new_mode))) != 0) return 1;
        return 0;
    } else if (c == 'n' or c == 'N') {
        var st: core.c.struct_stat = undefined;
        if (core.c.stat(tty, &st) != 0) return 1;
        const new_mode = st.st_mode & ~@as(c_uint, 0o022);
        if (core.c.chmod(tty, @as(c_uint, @intCast(new_mode))) != 0) return 1;
        return 0;
    }
    return 1;
}
