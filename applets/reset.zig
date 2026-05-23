const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "reset", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;

    // RIS - full reset
    _ = core.c.write(1, "\x1bc", 2);
    // Clear scroll region
    _ = core.c.write(1, "\x1b[r", 3);
    // Reset attributes
    _ = core.c.write(1, "\x1b[0m", 4);
    // Clear screen
    _ = core.c.write(1, "\x1b[2J", 4);
    // Cursor home
    _ = core.c.write(1, "\x1b[H", 3);

    // Try to reset terminal via termios
    var termios: [60]u8 = undefined; // struct termios is ~60 bytes
    if (core.c.ioctl(0, 0x5401, @as([*]u8, @ptrCast(&termios))) >= 0) { // TCGETS
        // Set reasonable defaults: 9600 baud, 8 bits, no parity, 1 stop bit
        // c_iflag: ICRNL, IXON, BRKINT
        // c_oflag: OPOST, ONLCR
        // c_cflag: CS8, CREAD, HUPCL
        // c_lflag: ISIG, ICANON, ECHO, ECHOE, ECHOK, ECHOKE
        // This is complex to set field by field without struct layout
        // Simpler: just write escape sequences (already done above)
    }

    return 0;
}
