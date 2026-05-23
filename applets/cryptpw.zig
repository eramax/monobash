const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "cryptpw", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var opt_method: ?[]const u8 = null;
    var opt_salt: ?[]const u8 = null;
    var opt_fd: ?usize = null;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (args[i].len == 1) { i += 1; break; }
        if (args[i][1] == 'm' or args[i][1] == 'a') {
            i += 1;
            if (i >= args.len) return core.die(1, "cryptpw: -m requires argument\n", .{});
            opt_method = args[i];
        } else if (args[i][1] == 'S') {
            i += 1;
            if (i >= args.len) return core.die(1, "cryptpw: -S requires argument\n", .{});
            opt_salt = args[i];
        } else if (args[i][1] == 'P') {
            i += 1;
            if (i >= args.len) return core.die(1, "cryptpw: -P requires argument\n", .{});
            opt_fd = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "cryptpw: invalid fd\n", .{});
        } else if (args[i][1] == 's') {
            opt_fd = 0;
        } else return core.die(1, "cryptpw: unknown option -{c}\n", .{args[i][1]});
        i += 1;
    }

    var password: ?[]const u8 = null;
    if (i < args.len) {
        password = args[i];
        i += 1;
        if (opt_salt == null and i < args.len) {
            opt_salt = args[i];
        }
    }

    var salt_buf: [256]u8 = undefined;
    if (opt_salt) |s| {
        const n = @min(s.len, salt_buf.len - 1);
        @memcpy(salt_buf[0..n], s[0..n]);
        salt_buf[n] = 0;
    } else {
        const method = opt_method orelse "des";
        const mlen = @min(method.len, 16);
        var zbuf: [32:0]u8 = undefined;
        @memcpy(zbuf[0..mlen], method[0..mlen]);
        zbuf[mlen] = 0;
        const sp = core.c.crypt_gensalt_ra(zbuf[0..mlen :0].ptr, @as(c_ulong, 0), null, @as(c_int, 0));
        if (sp) |s| {
            const slen = std.mem.len(s);
            const n = @min(slen, salt_buf.len - 1);
            @memcpy(salt_buf[0..n], @as([*]u8, @ptrCast(s))[0..n]);
            salt_buf[n] = 0;
        } else {
            _ = std.fmt.bufPrint(&salt_buf, "$1${s}",
                .{@as([]const u8, "abcdefgh")}) catch return 1;
        }
    }

    if (password == null) {
        if (opt_fd) |fd| {
            const buf = core.readAll(alloc, @as(c_int, @intCast(fd)), 4096) catch return 1;
            password = std.mem.trim(u8, buf, "\n\r ");
        } else {
            const buf = core.readAll(alloc, 0, 4096) catch return 1;
            password = std.mem.trim(u8, buf, "\n\r ");
        }
    }

    const pwd = password orelse "";
    const pwd_z = alloc.dupeZ(u8, pwd) catch return 1;
    const result = core.c.crypt(pwd_z.ptr, salt_buf[0..std.mem.indexOfScalar(u8, salt_buf[0..], 0) orelse salt_buf.len :0].ptr);
    if (result == null) return core.die(1, "cryptpw: crypt failed\n", .{});

    const hash = std.mem.sliceTo(@as([*c]u8, @ptrCast(result)), 0);
    core.writeAll(1, hash);
    core.writeAll(1, "\n");
    return 0;
}
