const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "pinky", .main = main };

pub fn main(_: [][]const u8) u8 {
    const pw = core.c.getpwuid(core.c.getuid());
    if (pw == null) return 1;
    const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_name)), 0);
    const gecos = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_gecos)), 0);
    const dir = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_dir)), 0);
    const shell = std.mem.sliceTo(@as([*c]u8, @ptrCast(pw.*.pw_shell)), 0);
    core.writeAll(1, "Login: ");
    core.writeAll(1, name);
    core.writeAll(1, "    Name: ");
    const gecos_trim = if (std.mem.indexOfScalar(u8, gecos, ',')) |comma| gecos[0..comma] else gecos;
    core.writeAll(1, if (gecos_trim.len > 0) gecos_trim else "(none)");
    core.writeAll(1, "\n");
    core.writeAll(1, "Directory: ");
    core.writeAll(1, dir);
    core.writeAll(1, "    Shell: ");
    core.writeAll(1, shell);
    core.writeAll(1, "\n");
    return 0;
}
