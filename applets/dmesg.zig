const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dmesg", .main = main };

extern "c" fn klogctl(type: c_int, buf: ?[*]u8, len: c_int) c_int;

const SYSLOG_ACTION_READ_ALL: c_int = 3;
const SYSLOG_ACTION_SIZE_BUFFER: c_int = 10;

pub fn main(_: [][]const u8) u8 {
    const size = klogctl(SYSLOG_ACTION_SIZE_BUFFER, null, 0);
    if (size <= 0) return core.die(1, "dmesg: klogctl failed (permission denied)\n", .{});
    const buf = std.heap.page_allocator.alloc(u8, @intCast(size)) catch return 1;
    defer std.heap.page_allocator.free(buf);
    const n = klogctl(SYSLOG_ACTION_READ_ALL, buf.ptr, @intCast(size));
    if (n < 0) return core.die(1, "dmesg: read failed\n", .{});
    core.writeAll(1, buf[0..@intCast(n)]);
    return 0;
}
