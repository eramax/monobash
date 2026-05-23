const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "groups", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len <= 1) {
        return printCurrent();
    }
    var ec: u8 = 0;
    for (args[1..]) |user| {
        ec |= printForUser(user);
    }
    return ec;
}

fn printCurrent() u8 {
    const gid = core.c.getgid();

    var gr = core.c.getgrgid(gid);
    const pname = if (gr != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(gr.*.gr_name)), 0) else "";
    if (pname.len > 0) core.writeAll(1, pname);

    var gids: [128]u32 = undefined;
    const n = core.c.getgroups(@intCast(gids.len), &gids);
    if (n >= 0) {
        for (0..@as(usize, @intCast(n))) |i| {
            core.writeAll(1, " ");
            gr = core.c.getgrgid(gids[i]);
            const name = if (gr != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(gr.*.gr_name)), 0) else "";
            if (name.len > 0) {
                core.writeAll(1, name);
            } else {
                var buf: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{gids[i]}) catch "";
                core.writeAll(1, s);
            }
        }
    }
    core.writeAll(1, "\n");
    return 0;
}

fn printForUser(user: []const u8) u8 {
    var ubuf: [256:0]u8 = undefined;
    if (user.len >= ubuf.len) {
        core.eprint("groups: user name too long\n", .{});
        return 1;
    }
    @memcpy(ubuf[0..user.len], user);
    ubuf[user.len] = 0;

    const pw = core.c.getpwnam(&ubuf);
    if (pw == null) {
        core.eprint("groups: {s}: no such user\n", .{user});
        return 1;
    }

    core.writeAll(1, user);
    core.writeAll(1, " : ");

    var gr = core.c.getgrgid(pw.*.pw_gid);
    const pname = if (gr != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(gr.*.gr_name)), 0) else "";
    if (pname.len > 0) core.writeAll(1, pname);

    var ngroups: c_int = 128;
    var gids: [128]u32 = undefined;
    const rc = core.c.getgrouplist(&ubuf, pw.*.pw_gid, &gids, &ngroups);
    if (rc >= 0) {
        for (0..@as(usize, @intCast(ngroups))) |i| {
            core.writeAll(1, " ");
            gr = core.c.getgrgid(gids[i]);
            const name = if (gr != null) std.mem.sliceTo(@as([*c]u8, @ptrCast(gr.*.gr_name)), 0) else "";
            if (name.len > 0) {
                core.writeAll(1, name);
            } else {
                var buf: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{gids[i]}) catch "";
                core.writeAll(1, s);
            }
        }
    }
    core.writeAll(1, "\n");
    return 0;
}
