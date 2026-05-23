const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "stty", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var show_all = false;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "-a")) {
            show_all = true;
        } else if (std.mem.eql(u8, args[i], "--")) {
            i += 1;
            break;
        } else if (args[i].len > 0 and args[i][0] == '-') {
            return core.die(1, "stty: unknown option: {s}\n", .{args[i]});
        } else {
            break;
        }
        i += 1;
    }
    var term: core.c.termios = undefined;
    if (core.c.tcgetattr(0, &term) != 0) {
        return core.die(1, "stty: not a terminal\n", .{});
    }
    if (show_all) {
        core.writeAll(1, "speed 38400 baud; line 0;\n");
        core.writeAll(1, "intr = ^C; quit = ^\\; erase = ^?; kill = ^U; eof = ^D; eol = <undef>;\n");
        core.writeAll(1, "eol2 = <undef>; swtch = <undef>; start = ^Q; stop = ^S; susp = ^Z;\n");
        core.writeAll(1, "rprnt = ^R; werase = ^W; lnext = ^V; discard = ^O;\n");
        core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "cflags: {b:0>32}\n", .{term.c_cflag}) catch return 1);
        core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "iflags: {b:0>32}\n", .{term.c_iflag}) catch return 1);
        core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "oflags: {b:0>32}\n", .{term.c_oflag}) catch return 1);
        core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "lflags: {b:0>32}\n", .{term.c_lflag}) catch return 1);
        return 0;
    }
    if (i < args.len) {
        const speed = std.fmt.parseInt(c_uint, args[i], 10) catch {
            return core.die(1, "stty: invalid speed '{s}'\n", .{args[i]});
        };
        var speed_code: core.c.speed_t = undefined;
        if (speed <= 50) { speed_code = core.c.B50; }
        else if (speed <= 75) { speed_code = core.c.B75; }
        else if (speed <= 110) { speed_code = core.c.B110; }
        else if (speed <= 134) { speed_code = core.c.B134; }
        else if (speed <= 150) { speed_code = core.c.B150; }
        else if (speed <= 200) { speed_code = core.c.B200; }
        else if (speed <= 300) { speed_code = core.c.B300; }
        else if (speed <= 600) { speed_code = core.c.B600; }
        else if (speed <= 1200) { speed_code = core.c.B1200; }
        else if (speed <= 1800) { speed_code = core.c.B1800; }
        else if (speed <= 2400) { speed_code = core.c.B2400; }
        else if (speed <= 4800) { speed_code = core.c.B4800; }
        else if (speed <= 9600) { speed_code = core.c.B9600; }
        else if (speed <= 19200) { speed_code = core.c.B19200; }
        else if (speed <= 38400) { speed_code = core.c.B38400; }
        else if (speed <= 57600) { speed_code = core.c.B57600; }
        else if (speed <= 115200) { speed_code = core.c.B115200; }
        else { speed_code = core.c.B38400; }
        _ = core.c.cfsetispeed(&term, speed_code);
        _ = core.c.cfsetospeed(&term, speed_code);
        if (core.c.tcsetattr(0, core.c.TCSANOW, &term) != 0) {
            return core.die(1, "stty: tcsetattr failed\n", .{});
        }
        return 0;
    }
    {
        const ispeed = core.c.cfgetispeed(&term);
        const ospeed = core.c.cfgetospeed(&term);
        var speed_str: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&speed_str, "speed {d} baud\n", .{@as(c_uint, @intCast(ispeed))}) catch "unknown\n";
        core.writeAll(1, s);
        _ = ospeed;
    }
    return 0;
}
