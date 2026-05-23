const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "seq", .main = main };

fn parseFloat(s: []const u8) ?f64 {
    return std.fmt.parseFloat(f64, s) catch null;
}

fn getPrecision(s: []const u8) usize {
    if (std.mem.indexOfScalar(u8, s, '.')) |dot| {
        return s.len - dot - 1;
    }
    return 0;
}

fn intPartWidth(s: []const u8) usize {
    var start: usize = 0;
    if (s.len > 0 and (s[0] == '+' or s[0] == '-')) start = 1;
    if (std.mem.indexOfScalar(u8, s, '.')) |dot| {
        return @max(1, dot - start);
    }
    return @max(1, s.len - start);
}

fn formatNum(buf: []u8, v: f64, precision: usize, int_width: usize, do_pad: bool) []const u8 {
    const sign_bit: u64 = @as(u64, @bitCast(v));
    const is_neg = sign_bit >> 63 == 1;
    const sign = if (is_neg) "-" else "";
    const abs_v = if (is_neg) -v else v;

    var int_buf: [128]u8 = undefined;
    const int_str = std.fmt.bufPrint(&int_buf, "{d}", .{@as(i64, @intFromFloat(@floor(abs_v + 1e-12)))}) catch "0";

    var padded_buf: [128]u8 = undefined;
    var int_out: []const u8 = int_str;
    if (do_pad) {
        const pad_len = if (int_width > int_str.len) int_width - int_str.len else 0;
        if (pad_len > 0) {
            @memset(padded_buf[0..pad_len], '0');
            @memcpy(padded_buf[pad_len..][0..int_str.len], int_str);
            int_out = padded_buf[0 .. pad_len + int_str.len];
        }
    }

    if (precision > 0) {
        const factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(precision)));
        const frac_val = @round((abs_v - @floor(abs_v + 1e-12)) * factor);
        const frac_abs = @as(u64, @intFromFloat(@abs(frac_val)));
        var frac_buf: [128]u8 = undefined;
        const raw = std.fmt.bufPrint(&frac_buf, "{d}", .{frac_abs}) catch "0";
        var padded: [128]u8 = undefined;
        const frac_str = if (raw.len < precision) blk: {
            @memset(padded[0 .. precision - raw.len], '0');
            @memcpy(padded[precision - raw.len ..][0..raw.len], raw);
            break :blk padded[0..precision];
        } else raw;
        return std.fmt.bufPrint(buf, "{s}{s}.{s}", .{sign, int_out, frac_str}) catch "";
    } else {
        return std.fmt.bufPrint(buf, "{s}{s}", .{sign, int_out}) catch "";
    }
}

pub fn main(args: [][]const u8) u8 {
    var separator: []const u8 = "\n";
    var do_pad_width: bool = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        }
        if (std.mem.eql(u8, arg, "-w")) {
            do_pad_width = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) return core.die(1, "seq: missing argument after -s\n", .{});
            separator = args[i];
            i += 1;
        } else if (arg.len > 1 and ((arg[1] >= '0' and arg[1] <= '9') or arg[1] == '.' or arg[1] == '-')) {
            break;
        } else {
            return core.die(1, "seq: invalid option -- '{c}'\n", .{if (arg.len > 1) arg[1] else '?'});
        }
    }

    const num_args = args[i..];
    if (num_args.len < 1) return core.die(1, "seq: missing operand\n", .{});
    if (num_args.len > 3) return core.die(1, "seq: too many operands\n", .{});

    var first: f64 = 1.0;
    var inc: f64 = 1.0;
    var last: f64 = undefined;

    var first_s: []const u8 = "1";
    var inc_s: []const u8 = "1";
    var last_s: []const u8 = undefined;

    if (num_args.len == 1) {
        last = parseFloat(num_args[0]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[0]});
        last_s = num_args[0];
    } else if (num_args.len == 2) {
        first = parseFloat(num_args[0]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[0]});
        last = parseFloat(num_args[1]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[1]});
        first_s = num_args[0];
        last_s = num_args[1];
    } else if (num_args.len == 3) {
        first = parseFloat(num_args[0]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[0]});
        inc = parseFloat(num_args[1]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[1]});
        last = parseFloat(num_args[2]) orelse return core.die(1, "seq: invalid number: {s}\n", .{num_args[2]});
        first_s = num_args[0];
        inc_s = num_args[1];
        last_s = num_args[2];
    }

    const prec = @max(getPrecision(first_s), getPrecision(inc_s));
    const int_width = @max(@max(intPartWidth(first_s), intPartWidth(inc_s)), intPartWidth(last_s));

    var outbuf: [8192]u8 = undefined;

    var v = if (num_args.len == 1) @as(f64, 1.0) else first;
    const limit = last;
    const step = inc;
    var first_val = true;

    if (step == 0.0) {
        while (true) {
            if (!first_val) { if (core.c.write(1, separator.ptr, separator.len) < 0) break; }
            const s = formatNum(&outbuf, v, prec, int_width, do_pad_width);
            if (core.c.write(1, s.ptr, s.len) < 0) break;
            first_val = false;
        }
    } else if (step > 0) {
        while (v <= limit + 1e-12) {
            if (!first_val) core.writeAll(1, separator);
            const s = formatNum(&outbuf, v, prec, int_width, do_pad_width);
            core.writeAll(1, s);
            first_val = false;
            v += step;
        }
    } else {
        while (v >= limit - 1e-12) {
            if (!first_val) core.writeAll(1, separator);
            const s = formatNum(&outbuf, v, prec, int_width, do_pad_width);
            core.writeAll(1, s);
            first_val = false;
            v += step;
        }
    }

    if (!first_val) core.writeAll(1, "\n");
    return 0;
}
