const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "passwd", .main = main };

fn updateShadow(user_z: [:0]const u8, new_hash_z: [:0]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const tmp_z = alloc.dupeZ(u8, "/etc/shadow.tmp") catch return 1;
    defer alloc.free(tmp_z);
    const tf = core.c.fopen(tmp_z.ptr, "w") orelse return core.die(1, "passwd: cannot open /etc/shadow\n", .{});
    defer _ = core.c.fclose(tf);
    var found = false;
    core.c.setspent();
    while (core.c.getspent()) |s| {
        const sn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(s.*.sp_namp)), 0);
        if (std.mem.eql(u8, sn, std.mem.sliceTo(user_z, 0))) {
            var updated = s.*;
            updated.sp_pwdp = @constCast(new_hash_z.ptr);
            updated.sp_lstchg = @intCast(@divTrunc(core.c.time(null), @as(c_long, 86400)));
            _ = core.c.putspent(&updated, tf);
            found = true;
        } else {
            _ = core.c.putspent(s, tf);
        }
    }
    core.c.endspent();
    _ = core.c.fclose(tf);
    if (!found) return core.die(1, "passwd: no shadow entry\n", .{});
    const shadow_z = alloc.dupeZ(u8, "/etc/shadow") catch return 1;
    defer alloc.free(shadow_z);
    return if (core.c.rename(tmp_z.ptr, shadow_z.ptr) < 0)
        core.die(1, "passwd: failed to update /etc/shadow\n", .{}) else 0;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    const is_root = core.c.geteuid() == 0;

    var target_user: []const u8 = "";
    if (args.len > 1) target_user = args[1];

    // Determine target user
    const target: []const u8 = if (target_user.len > 0) target_user else blk: {
        const pw = core.c.getpwuid(core.c.getuid()) orelse
            return core.die(1, "passwd: cannot determine current user\n", .{});
        break :blk std.mem.sliceTo(@as([*:0]const u8, @ptrCast(pw.*.pw_name)), 0);
    };

    // Non-root can only change own password
    if (!is_root) {
        const uid = core.c.getuid();
        const pw = core.c.getpwuid(uid) orelse
            return core.die(1, "passwd: unknown user\n", .{});
        const self_name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(pw.*.pw_name)), 0);
        if (!std.mem.eql(u8, self_name, target))
            return core.die(1, "passwd: only root can change other users' passwords\n", .{});

        // Delegate to real passwd via exec
        const target_z = alloc.dupeZ(u8, target) catch return 1;
        _ = core.c.execle("passwd", "passwd", target_z.ptr, @as(?*anyopaque, null));
        return core.die(1, "passwd: cannot execute real passwd (needs SUID)\n", .{});
    }

    // Root: do it ourselves
    const target_z = alloc.dupeZ(u8, target) catch return 1;
    defer alloc.free(target_z);
    _ = core.c.getpwnam(target_z.ptr) orelse
        return core.die(1, "passwd: user '{s}' does not exist\n", .{target});

    // Read old shadow entry
    const sp = core.c.getspnam(target_z.ptr) orelse
        return core.die(1, "passwd: no shadow entry for '{s}'\n", .{target});

    // Prompt for old password (unless root setting own or --stdin)
    const stdin_fd = core.c.STDIN_FILENO;
    var old_buf: [256]u8 = undefined;
    if (!is_root) {
        core.writeAll(2, "Current password: ");
        var pos: usize = 0;
        while (pos < old_buf.len) {
            var ch: u8 = undefined;
            const n = core.c.read(stdin_fd, &ch, 1);
            if (n <= 0) return 1;
            old_buf[pos] = ch;
            if (ch == '\n') break;
            pos += 1;
        }
        const old_z = alloc.dupeZ(u8, old_buf[0..pos]) catch return 1;
        defer alloc.free(old_z);
        const check = core.c.crypt(old_z.ptr, sp.*.sp_pwdp);
        if (check == null or !std.mem.eql(u8, std.mem.sliceTo(@as([*:0]const u8, check), 0), std.mem.sliceTo(sp.*.sp_pwdp, 0)))
            return core.die(1, "passwd: incorrect password\n", .{});
    }

    // Prompt for new password
    core.writeAll(2, "New password: ");
    var new_buf: [256]u8 = undefined;
    var pos2: usize = 0;
    while (pos2 < new_buf.len) {
        var ch2: u8 = undefined;
        const n2 = core.c.read(stdin_fd, &ch2, 1);
        if (n2 <= 0) return 1;
        new_buf[pos2] = ch2;
        if (ch2 == '\n') break;
        pos2 += 1;
    }
    const new1 = new_buf[0..pos2];

    core.writeAll(2, "Retype new password: ");
    var confirm_buf: [256]u8 = undefined;
    var pos3: usize = 0;
    while (pos3 < confirm_buf.len) {
        var ch3: u8 = undefined;
        const n3 = core.c.read(stdin_fd, &ch3, 1);
        if (n3 <= 0) return 1;
        confirm_buf[pos3] = ch3;
        if (ch3 == '\n') break;
        pos3 += 1;
    }
    if (!std.mem.eql(u8, new1, confirm_buf[0..pos3]))
        return core.die(1, "passwd: passwords do not match\n", .{});
    if (new1.len == 0)
        return core.die(1, "passwd: password cannot be empty\n", .{});

    const new1_z = alloc.dupeZ(u8, new1) catch return 1;
    defer alloc.free(new1_z);
    const new_hash = core.c.crypt(new1_z.ptr, sp.*.sp_pwdp);
    if (new_hash == null) return core.die(1, "passwd: crypt failed\n", .{});
    const new_hash_z = alloc.dupeZ(u8, std.mem.sliceTo(@as([*:0]const u8, new_hash), 0)) catch return 1;
    defer alloc.free(new_hash_z);

    return updateShadow(target_z, new_hash_z);
}
