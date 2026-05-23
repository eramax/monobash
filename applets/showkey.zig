const std = @import("std");
const core = @import("core.zig");
const KDGKBMODE: u32 = 0x4B44;
const KDSKBMODE: u32 = 0x4B45;
const K_RAW: c_int = 0;
const K_MEDIUMRAW: c_int = 2;
pub const meta = core.AppletMeta{ .name = "showkey", .main = main };
pub fn main(args: [][]const u8) u8 {
    var mode: u32 = 0;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "-s")) {
                mode = 0;
            } else if (std.mem.eql(u8, args[i], "-k")) {
                mode = 1;
            } else if (std.mem.eql(u8, args[i], "-a")) {
                mode = 2;
            } else {
                return core.die(1, "usage: showkey [-a | -k | -s]\n", .{});
            }
        }
    }
    var old_termios: core.c.struct_termios = undefined;
    var raw_termios: core.c.struct_termios = undefined;
    _ = core.c.tcgetattr(core.c.STDIN_FILENO, &old_termios);
    raw_termios = old_termios;
    core.c.cfmakeraw(&raw_termios);
    _ = core.c.tcsetattr(core.c.STDIN_FILENO, 2, &raw_termios);
    defer _ = core.c.tcsetattr(core.c.STDIN_FILENO, 2, &old_termios);
    if (mode == 2) {
        core.writeAll(1, "Press any keys, program terminates on EOF (ctrl-D):\r\n\n");
        var c: u8 = 0;
        while (core.c.read(core.c.STDIN_FILENO, @as([*]u8, @ptrCast(&c)), 1) == 1) {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d:3} 0{o:3} 0x{x:2}\r\n", .{c, c, c}) catch break;
            core.writeAll(1, s);
            if (c == 4) break;
        }
    } else {
        var old_kbmode: c_int = 0;
        _ = core.c.ioctl(core.c.STDIN_FILENO, KDGKBMODE, &old_kbmode);
        const new_kbmode: c_int = if (mode == 1) K_MEDIUMRAW else K_RAW;
        _ = core.c.ioctl(core.c.STDIN_FILENO, KDSKBMODE, new_kbmode);
        defer _ = core.c.ioctl(core.c.STDIN_FILENO, KDSKBMODE, old_kbmode);
        core.writeAll(1, "Press any keys, program terminates 10s after last keypress:\r\n\n");
        var buf: [18]u8 = undefined;
        while (true) {
            _ = core.c.alarm(10);
            const n = core.c.read(core.c.STDIN_FILENO, &buf, 18);
            if (n <= 0) break;
            var pos: usize = 0;
            while (pos < n) {
                if (mode == 0) {
                    var line: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&line, "0x{x:2} ", .{buf[pos]}) catch break;
                    core.writeAll(1, s);
                    pos += 1;
                } else {
                    var kc: u32 = 0;
                    if (pos + 2 < n and (buf[pos] & 0x7f) == 0 and (buf[pos+1] & 0x80) != 0 and (buf[pos+2] & 0x80) != 0) {
                        kc = ((buf[pos+1] & 0x7f) << 7) | (buf[pos+2] & 0x7f);
                        pos += 3;
                    } else {
                        kc = buf[pos] & 0x7f;
                        pos += 1;
                    }
                    const release = (buf[pos-1] & 0x80) != 0;
                    var line: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&line, "keycode {d:3} {s}\r\n", .{kc, if (release) "release" else "press"}) catch break;
                    core.writeAll(1, s);
                }
            }
            core.writeAll(1, "\r");
        }
    }
    return 0;
}
