const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "chown", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return 1;
    const owner_str = args[1];
    const path = args[2];
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return 1;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const colon = std.mem.indexOfScalar(u8, owner_str, ':');
    if (colon) |idx| {
        const user = owner_str[0..idx];
        const group = owner_str[idx + 1 ..];
        const uid = if (user.len > 0) parseUid(user) else @as(u32, @bitCast(@as(c_int, -1)));
        const gid = if (group.len > 0) parseGid(group) else @as(u32, @bitCast(@as(c_int, -1)));
        if (uid == null or gid == null) return 1;
        return if (core.c.chown(&buf, uid.?, gid.?) == 0) 0 else 1;
    }
    const uid = parseUid(owner_str) orelse return 1;
    return if (core.c.chown(&buf, uid, @bitCast(@as(c_int, -1))) == 0) 0 else 1;
}

fn parseUid(s: []const u8) ?u32 {
    if (std.fmt.parseInt(u32, s, 10)) |n| return n else |_| {}
    var z: [256:0]u8 = undefined;
    if (s.len >= z.len) return null;
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    const pw = core.c.getpwnam(&z);
    return if (pw != null) pw.*.pw_uid else null;
}

fn parseGid(s: []const u8) ?u32 {
    if (std.fmt.parseInt(u32, s, 10)) |n| return n else |_| {}
    var z: [256:0]u8 = undefined;
    if (s.len >= z.len) return null;
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    const gr = core.c.getgrnam(&z);
    return if (gr != null) gr.*.gr_gid else null;
}
