const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "adduser", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "adduser: only root can add users\n", .{});
    if (args.len < 2) return core.die(1, "usage: adduser [OPTIONS] USER\n", .{});
    const alloc = std.heap.page_allocator;

    var opt_uid: ?c_uint = null;
    var opt_gid: ?c_uint = null;
    var opt_home: []const u8 = "";
    var opt_shell: []const u8 = "/bin/bash";
    var opt_gecos: []const u8 = "";
    var name: []const u8 = "";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-u") and i + 1 < args.len) { i += 1; opt_uid = std.fmt.parseUnsigned(c_uint, args[i], 10) catch return core.die(1, "adduser: invalid UID\n", .{}); }
        else if (std.mem.eql(u8, args[i], "-g") and i + 1 < args.len) { i += 1; opt_gid = std.fmt.parseUnsigned(c_uint, args[i], 10) catch return core.die(1, "adduser: invalid GID\n", .{}); }
        else if (std.mem.eql(u8, args[i], "-h") and i + 1 < args.len) { i += 1; opt_home = args[i]; }
        else if (std.mem.eql(u8, args[i], "-s") and i + 1 < args.len) { i += 1; opt_shell = args[i]; }
        else if (std.mem.eql(u8, args[i], "-G") and i + 1 < args.len) { i += 1; opt_gecos = args[i]; }
        else if (name.len == 0) { name = args[i]; } else {
            return core.die(1, "adduser: extra argument '{s}'\n", .{args[i]});
        }
    }
    if (name.len == 0) return core.die(1, "usage: adduser USER\n", .{});

    const name_z = alloc.dupeZ(u8, name) catch return 1;
    defer alloc.free(name_z);
    if (core.c.getpwnam(name_z.ptr)) |_| return core.die(1, "adduser: user '{s}' already exists\n", .{name});

    const uid = if (opt_uid) |u| u else blk: {
        var max: c_uint = 999;
        core.c.setpwent();
        while (core.c.getpwent()) |pw| {
            if (@as(c_uint, @intCast(pw.*.pw_uid)) > max) max = @intCast(pw.*.pw_uid);
        }
        core.c.endpwent();
        break :blk if (max < 999) 1000 else max + 1;
    };
    const gid = opt_gid orelse uid;

    const home_z = if (opt_home.len > 0) alloc.dupeZ(u8, opt_home) catch return 1 else blk: {
        var hbuf: [4096]u8 = undefined;
        const h = std.fmt.bufPrint(&hbuf, "/home/{s}", .{name}) catch "/home";
        break :blk alloc.dupeZ(u8, h) catch return 1;
    };
    defer alloc.free(home_z);

    const shell_z = alloc.dupeZ(u8, opt_shell) catch return 1;
    defer alloc.free(shell_z);
    const gecos_z = alloc.dupeZ(u8, opt_gecos) catch return 1;
    defer alloc.free(gecos_z);

    // Create group if it doesn't exist
    if (core.c.getgrgid(@intCast(gid))) |_| {} else {
        const grp_name_z = alloc.dupeZ(u8, name) catch return 1;
        defer alloc.free(grp_name_z);
        var ngr = core.c.struct_group{
            .gr_name = @constCast(grp_name_z.ptr),
            .gr_passwd = @constCast("!"),
            .gr_gid = @intCast(gid),
            .gr_mem = null,
        };
        const tmp_z = alloc.dupeZ(u8, "/etc/group.tmp") catch return 1;
        defer alloc.free(tmp_z);
        const tf = core.c.fopen(tmp_z.ptr, "w") orelse return core.die(1, "adduser: cannot open group\n", .{});
        defer _ = core.c.fclose(tf);
        var written = false;
        core.c.setgrent();
        while (core.c.getgrent()) |gr| {
            if (!written and gr.*.gr_gid > gid) { _ = core.c.putgrent(&ngr, tf); written = true; }
            _ = core.c.putgrent(gr, tf);
        }
        if (!written) _ = core.c.putgrent(&ngr, tf);
        core.c.endgrent();
        _ = core.c.fclose(tf);
        const group_z = alloc.dupeZ(u8, "/etc/group") catch return 1;
        defer alloc.free(group_z);
        _ = core.c.rename(tmp_z.ptr, group_z.ptr);
    }

    // Add to /etc/passwd
    var pw = core.c.struct_passwd{
        .pw_name = @constCast(name_z.ptr),
        .pw_passwd = @constCast("x"),
        .pw_uid = @intCast(uid),
        .pw_gid = @intCast(gid),
        .pw_gecos = @constCast(gecos_z.ptr),
        .pw_dir = @constCast(home_z.ptr),
        .pw_shell = @constCast(shell_z.ptr),
    };
    const tmp2_z = alloc.dupeZ(u8, "/etc/passwd.tmp") catch return 1;
    defer alloc.free(tmp2_z);
    const tf2 = core.c.fopen(tmp2_z.ptr, "w") orelse return core.die(1, "adduser: cannot open passwd\n", .{});
    defer _ = core.c.fclose(tf2);
    var written2 = false;
    core.c.setpwent();
    while (core.c.getpwent()) |p| {
        if (!written2 and p.*.pw_uid > uid) { _ = core.c.putpwent(&pw, tf2); written2 = true; }
        _ = core.c.putpwent(p, tf2);
    }
    if (!written2) _ = core.c.putpwent(&pw, tf2);
    core.c.endpwent();
    _ = core.c.fclose(tf2);
    const passwd_z = alloc.dupeZ(u8, "/etc/passwd") catch return 1;
    defer alloc.free(passwd_z);
    if (core.c.rename(tmp2_z.ptr, passwd_z.ptr) < 0)
        return core.die(1, "adduser: failed to update /etc/passwd\n", .{});

    // Create home directory
    _ = core.c.mkdir(home_z.ptr, @as(c_uint, 0o755));
    _ = core.c.chown(home_z.ptr, @intCast(uid), @intCast(gid));

    // Also add shadow entry
    const tmp3_z = alloc.dupeZ(u8, "/etc/shadow.tmp") catch return 1;
    defer alloc.free(tmp3_z);
    const tf3 = core.c.fopen(tmp3_z.ptr, "w") orelse return 0;
    defer _ = core.c.fclose(tf3);
    var sp = core.c.struct_spwd{
        .sp_namp = @constCast(name_z.ptr),
        .sp_pwdp = @constCast("!"),
        .sp_lstchg = @intCast(@divTrunc(core.c.time(null), @as(c_long, 86400))),
        .sp_min = 0,
        .sp_max = 99999,
        .sp_warn = 7,
        .sp_inact = -1,
        .sp_expire = -1,
        .sp_flag = std.math.maxInt(c_ulong),
    };
    var written3 = false;
    core.c.setspent();
    while (core.c.getspent()) |s| {
        if (!written3) { _ = core.c.putspent(&sp, tf3); written3 = true; }
        _ = core.c.putspent(s, tf3);
    }
    if (!written3) _ = core.c.putspent(&sp, tf3);
    core.c.endspent();
    _ = core.c.fclose(tf3);
    const shadow_z = alloc.dupeZ(u8, "/etc/shadow") catch return 1;
    defer alloc.free(shadow_z);
    _ = core.c.rename(tmp3_z.ptr, shadow_z.ptr);

    return 0;
}
