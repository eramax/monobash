const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "uname", .main = main };

pub fn main(args: [][]const u8) u8 {
    var uts: core.c.struct_utsname = undefined;
    if (core.c.uname(&uts) != 0) return 1;

    const stdout = 1;
    var all = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "-a")) all = true;

    if (all) {
        printField(stdout, &uts.sysname);
        coreWrite(stdout, " ");
        printField(stdout, &uts.nodename);
        coreWrite(stdout, " ");
        printField(stdout, &uts.release);
        coreWrite(stdout, " ");
        printField(stdout, &uts.version);
        coreWrite(stdout, " ");
        printField(stdout, &uts.machine);
        coreWrite(stdout, "\n");
    } else {
        printField(stdout, &uts.sysname);
        coreWrite(stdout, "\n");
    }
    return 0;
}

fn coreWrite(fd: c_int, s: []const u8) void {
    _ = core.c.write(fd, s.ptr, s.len);
}

fn printField(fd: c_int, field: *const [65]u8) void {
    const len = std.mem.indexOfScalar(u8, field, @as(u8, 0)) orelse 65;
    _ = core.c.write(fd, @as([*]const u8, @ptrCast(field)), len);
}
