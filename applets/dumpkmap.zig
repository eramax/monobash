const std = @import("std");
const core = @import("core.zig");
const KDGKBENT: u32 = 0x4B46;
const NR_KEYS = 128;
const MAX_NR_KEYMAPS = 256;
const KbEntry = extern struct {
    kb_table: u8,
    kb_index: u8,
    kb_value: u16,
};
pub const meta = core.AppletMeta{ .name = "dumpkmap", .main = main };
pub fn main(args: [][]const u8) u8 {
    if (args.len > 1) return 1;
    const fd = core.c.open("/dev/tty0", core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "dumpkmap: cannot open /dev/tty0\n", .{});
    defer _ = core.c.close(fd);
    const header = [_]u8{ 'b', 'k', 'e', 'y', 'm', 'a', 'p' };
    core.writeAll(1, header[0..]);
    var flags: [MAX_NR_KEYMAPS]u8 = .{0} ** MAX_NR_KEYMAPS;
    const active_tables = [_]u8{ 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1 };
    for (active_tables, 0..) |v, i| flags[i] = v;
    core.writeAll(1, flags[0..]);
    var ke: KbEntry = undefined;
    for (0..13) |i| {
        if (flags[i] == 0) continue;
        for (0..NR_KEYS) |j| {
            ke.kb_index = @intCast(j);
            ke.kb_table = @intCast(i);
            if (core.c.ioctl(fd, KDGKBENT, &ke) >= 0) {
                var buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &buf, ke.kb_value, .little);
                core.writeAll(1, buf[0..]);
            }
        }
    }
    return 0;
}
