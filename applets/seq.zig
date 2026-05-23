const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "seq", .main = main };

fn parseFloat(s: []const u8) ?f64 {
    return std.fmt.parseFloat(f64, s) catch null;
}

fn formatNum(buf: []u8, v: f64) []const u8 {
    const as_int = @as(i64, @intFromFloat(v));
    if (@as(f64, @floatFromInt(as_int)) == v) {
        return std.fmt.bufPrint(buf, "{d}\n", .{as_int}) catch "";
    }
    var tmp: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}\n", .{v}) catch "";
    return std.fmt.bufPrint(buf, "{s}", .{s}) catch "";
}

pub fn main(args: [][]const u8) u8 {
    var first: f64 = 1.0;
    var inc: f64 = 1.0;
    var last: f64 = undefined;
    var mode: enum { last, first_last, first_inc_last } = .last;

    if (args.len < 2) return core.die(1, "seq: missing operand\n", .{});
    if (args.len > 4) return core.die(1, "seq: too many operands\n", .{});

    if (args.len == 2) {
        last = parseFloat(args[1]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[1]});
        mode = .last;
    } else if (args.len == 3) {
        first = parseFloat(args[1]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[1]});
        last = parseFloat(args[2]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[2]});
        mode = .first_last;
    } else if (args.len == 4) {
        first = parseFloat(args[1]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[1]});
        inc = parseFloat(args[2]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[2]});
        last = parseFloat(args[3]) orelse return core.die(1, "seq: invalid number: {s}\n", .{args[3]});
        mode = .first_inc_last;
    }

    if (inc == 0.0) return core.die(1, "seq: zero increment\n", .{});

    var outbuf: [4096]u8 = undefined;

    if (mode == .last) {
        var v: f64 = 1.0;
        while (v <= last) {
            const s = formatNum(&outbuf, v);
            core.writeAll(1, s);
            v += 1.0;
        }
    } else {
        var v = first;
        while (true) {
            if (inc > 0.0 and v > last) break;
            if (inc < 0.0 and v < last) break;
            const s = formatNum(&outbuf, v);
            core.writeAll(1, s);
            v += inc;
        }
    }

    return 0;
}
