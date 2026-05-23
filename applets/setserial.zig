const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "setserial", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    var opt_g = false;
    var opt_a = false;
    var opt_b = false;
    var opt_G = false;
    var opt_v = false;
    var opt_z = false;

    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        for (args[i][1..]) |c| {
            switch (c) {
                'g' => opt_g = true,
                'a' => opt_a = true,
                'b' => opt_b = true,
                'G' => opt_G = true,
                'v' => opt_v = true,
                'z' => opt_z = true,
                else => return core.die(1, "setserial: unknown option -{c}\n", .{c}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "usage: setserial [-abGvz] {{ DEVICE... | -g DEVICE... }}\n", .{});

    const print_mode: u8 = if (opt_a) 2 else if (opt_b) 0 else if (opt_G) 1 else 0;

    if (opt_g) {
        while (i < args.len) {
            const dev = args[i];
            const dev_z = alloc.dupeZ(u8, dev) catch return 1;
            const fd = core.c.open(dev_z.ptr, core.c.O_RDWR | core.c.O_NONBLOCK);
            if (fd >= 0) {
                var serinfo: core.c.struct_serial_struct = std.mem.zeroes(core.c.struct_serial_struct);
                if (core.c.ioctl(fd, core.c.TIOCGSERIAL, &serinfo) >= 0) {
                    core.writeAll(1, dev);
                    core.writeAll(1, ", UART: ");

                    const type_str = uartTypeName(serinfo.type);
                    core.writeAll(1, type_str);
                    var line: [128]u8 = undefined;
                    _ = std.fmt.bufPrint(&line, ", Port: 0x{x:0>4}, IRQ: {d}\n",
                        .{serinfo.port, serinfo.irq}) catch {};
                    break;
                }
                _ = core.c.close(fd);
            }
            i += 1;
        }
        return 0;
    }

    if (i + 1 >= args.len or opt_g) {
        while (i < args.len) {
            printDevice(args[i], print_mode) catch {};
            i += 1;
        }
        return 0;
    }

    const dev = args[i];
    const dev_z = alloc.dupeZ(u8, dev) catch return 1;
    const fd = core.c.open(dev_z.ptr, core.c.O_RDWR | core.c.O_NONBLOCK);
    if (fd < 0) return core.die(1, "setserial: cannot open {s}\n", .{dev});

    var serinfo: core.c.struct_serial_struct = undefined;
    if (core.c.ioctl(fd, core.c.TIOCGSERIAL, &serinfo) < 0) {
        _ = core.c.close(fd);
        return core.die(1, "setserial: cannot get serial info\n", .{});
    }

    if (opt_z) serinfo.flags = 0;

    var j = i + 1;
    while (j < args.len) {
        const word = args[j];
        j += 1;
        if (std.mem.eql(u8, word, "port")) {
            if (j >= args.len) return core.die(1, "setserial: port requires arg\n", .{});
            serinfo.port = @intCast(std.fmt.parseInt(u64, args[j], 0) catch return core.die(1, "setserial: bad port\n", .{}));
            j += 1;
        } else if (std.mem.eql(u8, word, "irq")) {
            if (j >= args.len) return core.die(1, "setserial: irq requires arg\n", .{});
            serinfo.irq = @intCast(std.fmt.parseInt(u64, args[j], 0) catch return core.die(1, "setserial: bad irq\n", .{}));
            j += 1;
        } else if (std.mem.eql(u8, word, "baud_base")) {
            if (j >= args.len) return core.die(1, "setserial: baud_base requires arg\n", .{});
            serinfo.baud_base = @intCast(std.fmt.parseInt(u64, args[j], 0) catch return core.die(1, "setserial: bad baud_base\n", .{}));
            j += 1;
        } else if (std.mem.eql(u8, word, "divisor")) {
            if (j >= args.len) return core.die(1, "setserial: divisor requires arg\n", .{});
            serinfo.custom_divisor = @intCast(std.fmt.parseInt(u64, args[j], 0) catch return core.die(1, "setserial: bad divisor\n", .{}));
            j += 1;
        } else if (std.mem.eql(u8, word, "uart")) {
            if (j >= args.len) return core.die(1, "setserial: uart requires arg\n", .{});
            j += 1;
        } else if (std.mem.eql(u8, word, "autoconfig")) {
            _ = core.c.ioctl(fd, core.c.TIOCSERCONFIG);
            _ = core.c.ioctl(fd, core.c.TIOCGSERIAL, &serinfo);
        } else if (std.mem.eql(u8, word, "spd_hi")) {
            serinfo.flags = @as(c_int, (serinfo.flags & ~@as(c_int, 38400)) | @as(c_int, 38400));
        } else if (std.mem.eql(u8, word, "spd_vhi")) {
            serinfo.flags = @as(c_int, (@as(c_int, serinfo.flags) & ~@as(c_int, core.c.ASYNC_SPD_MASK)) | core.c.ASYNC_SPD_VHI);
        } else if (std.mem.eql(u8, word, "spd_normal")) {
            serinfo.flags = @as(c_int, @as(c_int, serinfo.flags) & ~@as(c_int, core.c.ASYNC_SPD_MASK));
        } else if (word.len > 0 and word[0] == '^' and word.len > 1) {
            const flag = word[1..];
            if (std.mem.eql(u8, flag, "sak")) serinfo.flags = @as(c_int, @as(c_int, serinfo.flags) & ~@as(c_int, core.c.ASYNC_SAK));
        }
    }

    if (core.c.ioctl(fd, core.c.TIOCSSERIAL, &serinfo) < 0) {
        _ = core.c.close(fd);
        return core.die(1, "setserial: cannot set serial info\n", .{});
    }
    _ = core.c.close(fd);

    if (opt_v) {
        printDevice(dev, print_mode) catch {};
    }

    return 0;
}

fn uartTypeName(t: c_int) []const u8 {
    return switch (t) {
        0 => "unknown",
        1 => "8250",
        2 => "16450",
        3 => "16550",
        4 => "16550A",
        5 => "Cirrus",
        6 => "16650",
        7 => "16650V2",
        8 => "16750",
        9 => "16950",
        10 => "16954",
        11 => "16654",
        12 => "16850",
        13 => "RSA",
        14 => "NS16550A",
        15 => "XSCALE",
        16 => "RM9000",
        17 => "OCTEON",
        18 => "AR7",
        19 => "U6_16550A",
        else => "undefined",
    };
}

fn printDevice(dev: []const u8, _: u8) !void {
    const alloc = std.heap.page_allocator;
    const dev_z = try alloc.dupeZ(u8, dev);
    const fd = core.c.open(dev_z.ptr, core.c.O_RDWR | core.c.O_NONBLOCK);
    if (fd < 0) return error.OpenFailed;
    defer _ = core.c.close(fd);

    var serinfo: core.c.struct_serial_struct = undefined;
    if (core.c.ioctl(fd, core.c.TIOCGSERIAL, &serinfo) < 0) return error.IoctlFailed;

    const uart = uartTypeName(serinfo.type);
    const buf = try std.fmt.allocPrint(alloc, "{s}, UART: {s}, Port: 0x{x:0>4}, IRQ: {d}\n",
        .{dev, uart, serinfo.port, serinfo.irq});
    core.writeAll(1, buf);
}
