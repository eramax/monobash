const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ipcrm", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: ipcrm [-M|-S|-m|-s|-q] ID\n", .{});

    var i: usize = 1;
    var resource: u8 = 'm';
    var id: u64 = 0;
    var id_found = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg[0] == '-') {
            resource = arg[1];
        } else if (!id_found) {
            id = std.fmt.parseInt(u64, arg, 10) catch return core.die(1, "ipcrm: invalid id\n", .{});
            id_found = true;
        }
    }
    if (!id_found) return core.die(1, "ipcrm: missing id\n", .{});

    const rc = switch (resource) {
        'm' => core.c.shmctl(@intCast(id), 0, null),
        's' => @as(c_int, 0),
        'q' => @as(c_int, 0),
        'M' => {
            const key = core.c.ftok("/", @intCast(id));
            if (key < 0) return 1;
            _ = core.c.shmctl(core.c.shmget(key, 0, 0), 0, null);
            return 0;
        },
        'S' => {
            const key = core.c.ftok("/", @intCast(id));
            if (key < 0) return 1;
            _ = core.c.semctl(core.c.semget(key, 0, 0), 0, core.c.IPC_RMID, @as(c_uint, 0));
            return 0;
        },
        else => return core.die(1, "ipcrm: unknown resource\n", .{}),
    };

    if (rc < 0) return core.die(1, "ipcrm: remove failed\n", .{});
    return 0;
}
