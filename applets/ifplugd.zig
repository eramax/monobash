const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ifplugd", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var iface: []const u8 = "";
    var foreground = false;
    var poll_secs: u64 = 5;
    var script: []const u8 = "";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-i") and i + 1 < args.len) { i += 1; iface = args[i]; }
        if (std.mem.eql(u8, args[i], "-n")) foreground = true;
        if (std.mem.eql(u8, args[i], "-t") and i + 1 < args.len) { i += 1; poll_secs = std.fmt.parseInt(u64, args[i], 10) catch 5; }
        if (std.mem.eql(u8, args[i], "-r") and i + 1 < args.len) { i += 1; script = args[i]; }
    }

    if (iface.len == 0) return core.die(1, "ifplugd: missing -i IFACE\n", .{});

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_DGRAM, 0);
    if (sock < 0) return core.die(1, "ifplugd: socket\n", .{});

    var ifr: core.c.struct_ifreq = std.mem.zeroes(core.c.struct_ifreq);
    const nl = @min(iface.len, @as(usize, 15));
    @memcpy(ifr.ifr_ifrn.ifrn_name[0..nl], iface[0..nl]);

    var prev_up = false;
    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "ifplugd: monitoring {s} every {d}s\n", .{ iface, poll_secs }) catch "ifplugd: started\n";
    core.writeAll(1, m);

    while (true) {
        if (core.c.ioctl(sock, core.c.SIOCGIFFLAGS, &ifr) == 0) {
            const flags = ifr.ifr_ifru.ifru_flags;
            const up = (flags & 1) != 0;
            if (up != prev_up) {
                if (up) {
                    core.writeAll(1, "ifplugd: link up\n");
                } else {
                    core.writeAll(1, "ifplugd: link down\n");
                }
                if (script.len > 0) {
                    const action = if (up) "up" else "down";
                    const s = alloc.dupeZ(u8, script) catch continue;
                    if (s.len > 0) {
                        _ = core.c.fork();
                        _ = core.c.execle(s.ptr, s.ptr, iface.ptr, action.ptr, @as(?*anyopaque, null), @as(?*anyopaque, null));
                    }
                }
                prev_up = up;
            }
        }

        if (!foreground) { _ = core.c.sleep(@intCast(poll_secs)); }
        else {
            var tv: core.c.struct_timespec = .{ .tv_sec = @intCast(poll_secs), .tv_nsec = 0 };
            _ = core.c.nanosleep(&tv, null);
        }
    }
}
