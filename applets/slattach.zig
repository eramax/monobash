const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "slattach", .main = main };

const N_SLIP: c_int = 1;
const N_CSLIP: c_int = 2;
const N_SLIP6: c_int = 3;
const N_CSLIP6: c_int = 4;
const N_ADAPTIVE: c_int = 8;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: slattach [-p PROTO] [-s BAUD] TTY\n", .{});

    var i: usize = 1;
    var protocol: c_int = N_CSLIP;
    var baud_str: ?[]const u8 = null;
    var tty: ?[]const u8 = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") and i + 1 < args.len) {
            i += 1;
            const p = args[i];
            if (std.mem.eql(u8, p, "slip")) { protocol = N_SLIP; }
            else if (std.mem.eql(u8, p, "cslip")) { protocol = N_CSLIP; }
            else if (std.mem.eql(u8, p, "slip6")) { protocol = N_SLIP6; }
            else if (std.mem.eql(u8, p, "cslip6")) { protocol = N_CSLIP6; }
            else if (std.mem.eql(u8, p, "adaptive")) { protocol = N_ADAPTIVE; }
            else { return core.die(1, "slattach: unknown protocol\n", .{}); }
        } else if (std.mem.eql(u8, arg, "-s") and i + 1 < args.len) {
            i += 1;
            baud_str = args[i];
        } else {
            tty = arg;
        }
    }

    const tty_dev = tty orelse return core.die(1, "slattach: missing tty\n", .{});
    const tty_z = std.heap.page_allocator.dupeZ(u8, tty_dev) catch return 1;
    defer std.heap.page_allocator.free(tty_z);

    const fd = core.c.open(tty_z.ptr, core.c.O_RDWR);
    if (fd < 0) return core.die(1, "slattach: cannot open {s}\n", .{tty_dev});

    if (baud_str) |b| {
        const baud = std.fmt.parseInt(c_uint, b, 10) catch return core.die(1, "slattach: bad baud\n", .{});
        var tio: core.c.struct_termios = undefined;
        _ = core.c.tcgetattr(fd, &tio);
        _ = core.c.cfsetispeed(&tio, baud);
        _ = core.c.cfsetospeed(&tio, baud);
        _ = core.c.tcsetattr(fd, core.c.TCSANOW, &tio);
    }

    if (core.c.ioctl(fd, core.c.TIOCSETD, &protocol) < 0)
        return core.die(1, "slattach: TIOCSETD failed\n", .{});

    core.writeAll(1, "slattach: attached\n");
    _ = core.c.close(fd);
    return 0;
}
