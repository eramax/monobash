const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "truncate", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: truncate -s SIZE FILE...\n", .{});
    var i: usize = 1;
    var size: i64 = 0;
    var has_size = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i][0..2], "-s")) {
            const s = if (args[i].len > 2) args[i][2..] else blk: {
                i += 1;
                if (i < args.len) break :blk args[i] else return core.die(1, "truncate: missing size\n", .{});
            };
            if (s.len > 0) {
                if (s[0] == '+' or s[0] == '-') {
                    // relative size not supported, just parse absolute
                    size = std.fmt.parseInt(i64, s, 10) catch {
                        return core.die(1, "truncate: invalid size\n", .{});
                    };
                } else {
                    size = std.fmt.parseInt(i64, s, 10) catch {
                        return core.die(1, "truncate: invalid size\n", .{});
                    };
                }
                has_size = true;
            }
        }
        i += 1;
    }
    if (!has_size or i >= args.len) return core.die(1, "usage: truncate -s SIZE FILE...\n", .{});
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        var buf: [4096:0]u8 = undefined;
        if (args[i].len >= buf.len) { rc = 1; continue; }
        @memcpy(buf[0..args[i].len], args[i]);
        buf[args[i].len] = 0;
        if (core.c.truncate(&buf, size) != 0) {
            const fd = core.c.open(&buf, core.c.O_CREAT | core.c.O_WRONLY | core.c.O_TRUNC, @as(c_uint, 0o666));
            if (fd < 0 or core.c.ftruncate(fd, size) != 0) {
                core.eprint("truncate: cannot truncate '{s}'\n", .{args[i]});
                rc = 1;
            }
            if (fd >= 0) _ = core.c.close(fd);
        }
    }
    return rc;
}
