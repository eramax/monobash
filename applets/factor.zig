const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "factor", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "factor: missing operand\n", .{});
    for (args[1..]) |arg| {
        const n = std.fmt.parseUnsigned(u64, arg, 10) catch {
            core.eprint("factor: '{s}' is not a valid positive integer\n", .{arg});
            continue;
        };
        var buf: [512]u8 = undefined;
        var pos: usize = 0;
        @memcpy(buf[0..arg.len], arg);
        pos += arg.len;
        buf[pos] = ':'; pos += 1;
        buf[pos] = ' '; pos += 1;
        var m = n;
        var p: u64 = 2;
        while (p * p <= m) {
            while (m % p == 0) {
                const s = std.fmt.bufPrint(buf[pos..], " {d}", .{p}) catch break;
                pos += s.len;
                m /= p;
            }
            p += if (p == 2) 1 else 2;
        }
        if (m > 1) {
            const s = std.fmt.bufPrint(buf[pos..], " {d}", .{m}) catch "";
            pos += s.len;
        }
        buf[pos] = '\n'; pos += 1;
        core.writeAll(1, buf[0..pos]);
    }
    return 0;
}
