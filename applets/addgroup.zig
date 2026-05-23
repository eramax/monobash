const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "addgroup", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "addgroup: only root can add groups\n", .{});
    if (args.len < 2) return core.die(1, "usage: addgroup [-g GID] GROUP\n", .{});
    const alloc = std.heap.page_allocator;

    var opt_gid: ?c_uint = null;
    var name: []const u8 = "";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-g") and i + 1 < args.len) {
            i += 1;
            opt_gid = std.fmt.parseUnsigned(c_uint, args[i], 10) catch return core.die(1, "addgroup: invalid GID\n", .{});
        } else if (name.len == 0) {
            name = args[i];
        } else {
            return core.die(1, "usage: addgroup [-g GID] GROUP\n", .{});
        }
    }
    if (name.len == 0) return core.die(1, "usage: addgroup [-g GID] GROUP\n", .{});

    const name_z = alloc.dupeZ(u8, name) catch return 1;
    defer alloc.free(name_z);

    if (core.c.getgrnam(name_z.ptr)) |_| {
        return core.die(1, "addgroup: group '{s}' already exists\n", .{name});
    }

    const gid = if (opt_gid) |g| g else blk: {
        var max: c_uint = 999;
        core.c.setgrent();
        while (core.c.getgrent()) |gr| {
            if (gr.*.gr_gid > max) max = @intCast(gr.*.gr_gid);
        }
        core.c.endgrent();
        break :blk if (max < 999) 1000 else max + 1;
    };

    const tmp = alloc.dupeZ(u8, "/etc/group.tmp") catch return 1;
    defer alloc.free(tmp);
    const tmp_f = core.c.fopen(tmp.ptr, "w") orelse return core.die(1, "addgroup: cannot open group file\n", .{});
    defer _ = core.c.fclose(tmp_f);

    const new_gr = core.c.struct_group{
        .gr_name = @constCast(name_z.ptr),
        .gr_passwd = @constCast("*"),
        .gr_gid = @intCast(gid),
        .gr_mem = null,
    };
    var written = false;
    core.c.setgrent();
    while (core.c.getgrent()) |gr| {
        if (!written and gr.*.gr_gid > gid) {
            _ = core.c.putgrent(&new_gr, tmp_f);
            written = true;
        }
        _ = core.c.putgrent(gr, tmp_f);
    }
    if (!written) _ = core.c.putgrent(&new_gr, tmp_f);
    core.c.endgrent();
    _ = core.c.fclose(tmp_f);

    const group_z = alloc.dupeZ(u8, "/etc/group") catch return 1;
    defer alloc.free(group_z);
    if (core.c.rename(tmp.ptr, group_z.ptr) < 0)
        return core.die(1, "addgroup: failed to update /etc/group\n", .{});

    return 0;
}
