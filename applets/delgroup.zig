const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "delgroup", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "delgroup: only root can delete groups\n", .{});
    if (args.len < 2) return core.die(1, "usage: delgroup GROUP\n", .{});
    const alloc = std.heap.page_allocator;

    const name = args[1];
    const name_z = alloc.dupeZ(u8, name) catch return 1;
    defer alloc.free(name_z);

    if (core.c.getgrnam(name_z.ptr) == null)
        return core.die(1, "delgroup: group '{s}' does not exist\n", .{name});

    const tmp_z = alloc.dupeZ(u8, "/etc/group.tmp") catch return 1;
    defer alloc.free(tmp_z);
    const tf = core.c.fopen(tmp_z.ptr, "w") orelse return core.die(1, "delgroup: cannot open group\n", .{});
    defer _ = core.c.fclose(tf);

    var found = false;
    core.c.setgrent();
    while (core.c.getgrent()) |gr| {
        const gn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(gr.*.gr_name)), 0);
        if (std.mem.eql(u8, gn, name)) {
            found = true;
            continue;
        }
        _ = core.c.putgrent(gr, tf);
    }
    core.c.endgrent();
    _ = core.c.fclose(tf);

    if (!found) return core.die(1, "delgroup: group '{s}' not found\n", .{name});

    const group_z = alloc.dupeZ(u8, "/etc/group") catch return 1;
    defer alloc.free(group_z);
    if (core.c.rename(tmp_z.ptr, group_z.ptr) < 0)
        return core.die(1, "delgroup: failed to update /etc/group\n", .{});

    return 0;
}
