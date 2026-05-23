const std = @import("std");
const core = @import("core.zig");
const KDGKBMODE: u32 = 0x4B44;
const KDSKBMODE: u32 = 0x4B45;
const K_RAW: c_int = 0;
const K_XLATE: c_int = 1;
const K_MEDIUMRAW: c_int = 2;
const K_UNICODE: c_int = 3;
pub const meta = core.AppletMeta{ .name = "kbd_mode", .main = main };
pub fn main(args: [][]const u8) u8 {
    var fd: c_int = core.c.STDIN_FILENO;
    var own_fd: bool = false;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "-C") and i + 1 < args.len) {
                i += 1;
                const path = args[i];
                var buf: [4096:0]u8 = undefined;
                if (path.len >= buf.len) return 1;
                @memcpy(buf[0..path.len], path);
                buf[path.len] = 0;
                fd = core.c.open(&buf, core.c.O_RDONLY);
                if (fd < 0) return core.die(1, "kbd_mode: cannot open {s}\n", .{path});
                own_fd = true;
            }
        }
    }
    defer {
        if (own_fd) _ = core.c.close(fd);
    }
    var set_mode: ?c_int = null;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "-a")) {
                set_mode = K_XLATE;
            } else if (std.mem.eql(u8, args[i], "-k")) {
                set_mode = K_MEDIUMRAW;
            } else if (std.mem.eql(u8, args[i], "-s")) {
                set_mode = K_RAW;
            } else if (std.mem.eql(u8, args[i], "-u")) {
                set_mode = K_UNICODE;
            }
        }
    }
    if (set_mode) |mode| {
        _ = core.c.ioctl(fd, KDSKBMODE, mode);
    } else {
        var m: c_int = 0;
        if (core.c.ioctl(fd, KDGKBMODE, &m) < 0)
            return core.die(1, "kbd_mode: KDGKBMODE failed\n", .{});
        const s = if (m == K_RAW) "raw (scancode)"
            else if (m == K_XLATE) "default (ASCII)"
            else if (m == K_MEDIUMRAW) "mediumraw (keycode)"
            else if (m == K_UNICODE) "Unicode (UTF-8)"
            else "unknown";
        core.writeAll(1, "The keyboard is in ");
        core.writeAll(1, s);
        core.writeAll(1, " mode\n");
    }
    return 0;
}
