const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "numfmt", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "numfmt: missing operand\n", .{});
    const to_iec = std.mem.eql(u8, args[1], "--to=iec");
    if (!to_iec and !std.mem.eql(u8, args[1], "--from=iec"))
        return core.die(1, "numfmt: unknown option: {s}\n", .{args[1]});
    const val = args[2];
    var buf: [256]u8 = undefined;
    if (to_iec) {
        const n = std.fmt.parseFloat(f64, val) catch
            return core.die(1, "numfmt: invalid number: '{s}'\n", .{val});
        const units = [_]struct { limit: f64, suffix: []const u8 }{
            .{ .limit = 1152921504606846976.0, .suffix = "E" },
            .{ .limit = 1125899906842624.0, .suffix = "P" },
            .{ .limit = 1099511627776.0, .suffix = "T" },
            .{ .limit = 1073741824.0, .suffix = "G" },
            .{ .limit = 1048576.0, .suffix = "M" },
            .{ .limit = 1024.0, .suffix = "K" },
            .{ .limit = 1.0, .suffix = "" },
        };
        var i: usize = 0;
        while (i < units.len and n < units[i].limit) i += 1;
        if (i >= units.len) i = units.len - 1;
        const v = n / units[i].limit;
        if (units[i].suffix.len == 0) {
            const s = std.fmt.bufPrint(&buf, "{d}\n", .{n}) catch "";
            core.writeAll(1, s);
        } else {
            const s = std.fmt.bufPrint(&buf, "{d:.1}{s}\n", .{ v, units[i].suffix }) catch "";
            core.writeAll(1, s);
        }
    } else {
        if (std.fmt.parseFloat(f64, val)) |n| {
            const s = std.fmt.bufPrint(&buf, "{d}\n", .{n}) catch "";
            core.writeAll(1, s);
            return 0;
        } else |_| {}
        if (val.len < 2) return core.die(1, "numfmt: invalid value: '{s}'\n", .{val});
        const suffix = val[val.len - 1];
        const num_part = val[0 .. val.len - 1];
        const base = std.fmt.parseFloat(f64, num_part) catch
            return core.die(1, "numfmt: invalid value: '{s}'\n", .{val});
        const mult: f64 = switch (suffix) {
            'K', 'k' => 1024.0,
            'M', 'm' => 1048576.0,
            'G', 'g' => 1073741824.0,
            'T', 't' => 1099511627776.0,
            'P', 'p' => 1125899906842624.0,
            'E', 'e' => 1152921504606846976.0,
            else => return core.die(1, "numfmt: unknown suffix: '{c}'\n", .{suffix}),
        };
        const s = std.fmt.bufPrint(&buf, "{d}\n", .{base * mult}) catch "";
        core.writeAll(1, s);
    }
    return 0;
}
