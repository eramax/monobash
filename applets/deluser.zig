const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "deluser", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "deluser: only root can delete users\n", .{});
    if (args.len < 2) return core.die(1, "usage: deluser USER\n", .{});
    const alloc = std.heap.page_allocator;

    var remove_home = false;
    var name: []const u8 = "";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-r")) { remove_home = true; }
        else if (name.len == 0) { name = args[i]; }
        else return core.die(1, "usage: deluser [-r] USER\n", .{});
    }
    if (name.len == 0) return core.die(1, "usage: deluser USER\n", .{});

    const name_z = alloc.dupeZ(u8, name) catch return 1;
    defer alloc.free(name_z);

    const pw = core.c.getpwnam(name_z.ptr) orelse return core.die(1, "deluser: user '{s}' does not exist\n", .{name});

    // Remove from /etc/passwd
    {
        const tmp_z = alloc.dupeZ(u8, "/etc/passwd.tmp") catch return 1;
        defer alloc.free(tmp_z);
        const tf = core.c.fopen(tmp_z.ptr, "w") orelse return core.die(1, "deluser: cannot open passwd\n", .{});
        defer _ = core.c.fclose(tf);
        var found = false;
        core.c.setpwent();
        while (core.c.getpwent()) |p| {
            const pn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p.*.pw_name)), 0);
            if (std.mem.eql(u8, pn, name)) { found = true; continue; }
            _ = core.c.putpwent(p, tf);
        }
        core.c.endpwent();
        _ = core.c.fclose(tf);
        if (found) {
            const passwd_z = alloc.dupeZ(u8, "/etc/passwd") catch return 1;
            defer alloc.free(passwd_z);
            _ = core.c.rename(tmp_z.ptr, passwd_z.ptr);
        }
    }

    // Remove from /etc/shadow
    {
        const tmp_z = alloc.dupeZ(u8, "/etc/shadow.tmp") catch return 1;
        defer alloc.free(tmp_z);
        const tf = core.c.fopen(tmp_z.ptr, "w") orelse return 1;
        defer _ = core.c.fclose(tf);
        var found = false;
        core.c.setspent();
        while (core.c.getspent()) |s| {
            const sn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(s.*.sp_namp)), 0);
            if (std.mem.eql(u8, sn, name)) { found = true; continue; }
            _ = core.c.putspent(s, tf);
        }
        core.c.endspent();
        _ = core.c.fclose(tf);
        if (found) {
            const shadow_z = alloc.dupeZ(u8, "/etc/shadow") catch return 1;
            defer alloc.free(shadow_z);
            _ = core.c.rename(tmp_z.ptr, shadow_z.ptr);
        }
    }

    // Remove from /etc/group (remove user from all groups)
    {
        const tmp_z = alloc.dupeZ(u8, "/etc/group.tmp") catch return 1;
        defer alloc.free(tmp_z);
        const tf = core.c.fopen(tmp_z.ptr, "w") orelse return 1;
        defer _ = core.c.fclose(tf);
        core.c.setgrent();
        while (core.c.getgrent()) |gr| {
            const gn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(gr.*.gr_name)), 0);
            if (std.mem.eql(u8, gn, name)) continue;
            _ = core.c.putgrent(gr, tf);
        }
        core.c.endgrent();
        _ = core.c.fclose(tf);
        const group_z = alloc.dupeZ(u8, "/etc/group") catch return 1;
        defer alloc.free(group_z);
        _ = core.c.rename(tmp_z.ptr, group_z.ptr);
    }

    // Remove home directory if requested
    if (remove_home) {
        const dir = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(pw.*.pw_dir)), 0);
        _ = core.c.rmdir(dir.ptr);
    }

    return 0;
}
