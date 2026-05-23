const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "chpasswd", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (core.c.geteuid() != 0) return core.die(1, "chpasswd: only root can batch update passwords\n", .{});
    _ = args;
    const alloc = std.heap.page_allocator;

    var reader = core.LineReader.init(core.c.STDIN_FILENO);
    var rc: u8 = 0;

    while (reader.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
            core.eprint("chpasswd: invalid line (missing colon)\n", .{});
            rc = 1;
            continue;
        };
        const user = line[0..colon];
        const pass = line[colon + 1 ..];
        if (user.len == 0 or pass.len == 0) {
            core.eprint("chpasswd: empty user or password\n", .{});
            rc = 1;
            continue;
        }

        const user_z = alloc.dupeZ(u8, user) catch { rc = 1; continue; };
        defer alloc.free(user_z);

        _ = core.c.getpwnam(user_z.ptr) orelse {
            core.eprint("chpasswd: unknown user '{s}'\n", .{user});
            rc = 1;
            continue;
        };

        // Hash the new password
        var salt_buf: [32]u8 = undefined;
        const salt = std.fmt.bufPrint(&salt_buf, "$6$", .{}) catch unreachable;
        const salt_z = alloc.dupeZ(u8, salt) catch { rc = 1; continue; };
        const hashed = core.c.crypt(pass.ptr, salt_z.ptr);
        if (hashed == null) { rc = 1; continue; }

        // Read /etc/shadow, update entry, write back
        const tmp_z = alloc.dupeZ(u8, "/etc/shadow.tmp") catch { rc = 1; continue; };
        defer alloc.free(tmp_z);
        const tf = core.c.fopen(tmp_z.ptr, "w") orelse {
            core.eprint("chpasswd: cannot open /etc/shadow\n", .{});
            rc = 1;
            continue;
        };
        defer _ = core.c.fclose(tf);

        var found = false;
        core.c.setspent();
        while (core.c.getspent()) |s| {
            const sn = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(s.*.sp_namp)), 0);
            if (std.mem.eql(u8, sn, user)) {
                var updated = s.*;
                updated.sp_pwdp = @constCast(hashed);
                updated.sp_lstchg = @intCast(@divTrunc(core.c.time(null), @as(c_long, 86400)));
                _ = core.c.putspent(&updated, tf);
                found = true;
            } else {
                _ = core.c.putspent(s, tf);
            }
        }
        core.c.endspent();
        if (!found) {
            core.eprint("chpasswd: no shadow entry for '{s}'\n", .{user});
            rc = 1;
            continue;
        }
        _ = core.c.fclose(tf);
        const shadow_z = alloc.dupeZ(u8, "/etc/shadow") catch { rc = 1; continue; };
        defer alloc.free(shadow_z);
        if (core.c.rename(tmp_z.ptr, shadow_z.ptr) < 0) {
            core.eprint("chpasswd: failed to update /etc/shadow\n", .{});
            rc = 1;
        }
    }

    return rc;
}
