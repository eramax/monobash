const std = @import("std");
const core = @import("core.zig");
const KDSKBENT: u32 = 0x4B47;
const NR_KEYS = 128;
const MAX_NR_KEYMAPS = 256;
const KbEntry = extern struct {
    kb_table: u8,
    kb_index: u8,
    kb_value: u16,
};
pub const meta = core.AppletMeta{ .name = "loadkmap", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len > 1) return 1;
    const fd = core.c.open("/dev/tty0", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "loadkmap: cannot open /dev/tty0\n", .{});
    defer _ = core.c.close(fd);
    var magic: [7]u8 = undefined;
    if (core.c.read(core.c.STDIN_FILENO, &magic, 7) < 7 or !std.mem.eql(u8, magic[0..], "bkeymap"))
        return core.die(1, "loadkmap: not a valid binary keymap\n", .{});
    var flags: [MAX_NR_KEYMAPS]u8 = undefined;
    if (core.c.read(core.c.STDIN_FILENO, &flags, MAX_NR_KEYMAPS) < MAX_NR_KEYMAPS)
        return core.die(1, "loadkmap: short read\n", .{});
    var ke: KbEntry = undefined;
    for (0..MAX_NR_KEYMAPS) |i| {
        if (flags[i] != 1) continue;
        var ibuff: [NR_KEYS]u16 = undefined;
        const bytes = core.c.read(core.c.STDIN_FILENO, @as([*]u8, @ptrCast(&ibuff)), NR_KEYS * 2);
        if (bytes < NR_KEYS * 2) return core.die(1, "loadkmap: short read\n", .{});
        for (0..NR_KEYS) |j| {
            ke.kb_index = @intCast(j);
            ke.kb_table = @intCast(i);
            ke.kb_value = ibuff[j];
            _ = core.c.ioctl(fd, KDSKBENT, &ke);
        }
    }
    return 0;
}
