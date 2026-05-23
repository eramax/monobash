const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "printf", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 0;
    const fmt = args[1];
    const first_ai: usize = 2;
    var out: [65536]u8 = undefined;
    var last_result: u8 = 0;

    var cycle: usize = 0;
    var aborted = false;
    var ai = first_ai;
    while (true) {
        if (cycle > 0 and ai >= args.len) break;
        const prev_ai = ai;
        var bp: usize = 0;
        var fi: usize = 0;
        while (fi < fmt.len and bp < out.len) {
            if (fmt[fi] == '\\') {
                fi += 1;
                if (fi >= fmt.len) break;
                switch (fmt[fi]) {
                    'c' => { core.writeAll(1, out[0..bp]); return 0; },
                    '0'...'7' => { var v: u8 = 0; var n: usize = 0; while (fi < fmt.len and n < 3 and fmt[fi] >= '0' and fmt[fi] <= '7') : (n += 1) { v = v * 8 + (fmt[fi] - '0'); fi += 1; } out[bp] = v; bp += 1; },
                    'x' => { fi += 1; var v: u8 = 0; var n: usize = 0; while (fi < fmt.len and n < 2 and isHex(fmt[fi])) : (n += 1) { v = v * 16 + hexVal(fmt[fi]); fi += 1; } out[bp] = v; bp += 1; },
                    '\\' => { out[bp] = '\\'; bp += 1; fi += 1; },
                    'a' => { out[bp] = 7; bp += 1; fi += 1; },
                    'b' => { out[bp] = 8; bp += 1; fi += 1; },
                    'f' => { out[bp] = 12; bp += 1; fi += 1; },
                    'n' => { out[bp] = '\n'; bp += 1; fi += 1; },
                    'r' => { out[bp] = '\r'; bp += 1; fi += 1; },
                    't' => { out[bp] = '\t'; bp += 1; fi += 1; },
                    'v' => { out[bp] = 11; bp += 1; fi += 1; },
                    else => { out[bp] = '\\'; bp += 1; if (bp < out.len) { out[bp] = fmt[fi]; bp += 1; } fi += 1; },
                }
            } else if (fmt[fi] == '%') {
                fi += 1;
                if (fi >= fmt.len) { core.writeAll(2, "printf: %: invalid format\n"); last_result = 1; aborted = true; break; }
                if (fmt[fi] == '%') { out[bp] = '%'; bp += 1; fi += 1; continue; }

                var fbuf: [64]u8 = undefined;
                var fp: usize = 0;
                fbuf[fp] = '%'; fp += 1;
                // Flags
                while (fi < fmt.len and std.mem.indexOfScalar(u8, "-+ #0", fmt[fi]) != null) : (fi += 1) { fbuf[fp] = fmt[fi]; fp += 1; }
                // Width (may consume one arg if *)
                if (fi < fmt.len and fmt[fi] == '*') {
                    fi += 1;
                    var w: i64 = 0;
                    if (ai < args.len) { w = parseArgInt(args[ai], &last_result); ai += 1; }
                    if (w < 0) { w = -w; fbuf[fp] = '-'; fp += 1; }
                    var wb: [32]u8 = undefined;
                    const ws = std.fmt.bufPrint(&wb, "{d}", .{w}) catch "1";
                    for (ws) |c| { fbuf[fp] = c; fp += 1; }
                } else {
                    while (fi < fmt.len and fmt[fi] >= '0' and fmt[fi] <= '9') : (fi += 1) { fbuf[fp] = fmt[fi]; fp += 1; }
                }
                // Precision (may consume one arg if *)
                if (fi < fmt.len and fmt[fi] == '.') {
                    fbuf[fp] = '.'; fp += 1; fi += 1;
                    if (fi < fmt.len and fmt[fi] == '*') {
                        fi += 1;
                        if (ai < args.len) { const p = parseArgInt(args[ai], &last_result); ai += 1; if (p >= 0) { var pb: [32]u8 = undefined; const ps = std.fmt.bufPrint(&pb, "{d}", .{p}) catch "0"; for (ps) |c| { fbuf[fp] = c; fp += 1; } } else { fp -= 1; } } 
                        else { fp -= 1; }
                    } else {
                        while (fi < fmt.len and fmt[fi] >= '0' and fmt[fi] <= '9') : (fi += 1) { fbuf[fp] = fmt[fi]; fp += 1; }
                    }
                }
                // Length modifier
                while (fi < fmt.len and std.mem.indexOfScalar(u8, "hlLzj", fmt[fi]) != null) : (fi += 1) {}
                if (fi >= fmt.len) { core.writeAll(2, "printf: %: invalid format\n"); last_result = 1; aborted = true; break; }
                const spec = fmt[fi]; fi += 1;
                fbuf[fp] = spec; fp += 1;
                const fspec = fbuf[0..fp];

                // Get the argument for this spec
                const arg = if (ai < args.len) args[ai] else "";
                ai += 1;

                if (spec == 's') {
                    bp = fmtSprintf(out[0..], bp, fspec, arg);
                } else if (spec == 'b') {
                    bp = fmtB(out[0..], bp, arg);
                } else if (spec == 'q') {
                    bp = fmtQ(out[0..], bp, arg);
                } else if (spec == 'c') {
                    var cbuf: [2]u8 = [_]u8{if (arg.len > 0) arg[0] else 0, 0};
                    bp = fmtSprintf(out[0..], bp, fspec, cbuf[0..1]);
                } else if (spec == 'f' or spec == 'F') {
                    const val = parseFloatArg(arg, &last_result);
                    bp = fmtFloat(out[0..], bp, fspec, val);
                } else if (spec == 'd' or spec == 'i' or spec == 'u' or spec == 'o' or spec == 'x' or spec == 'X') {
                    const ival = parseArgInt(arg, &last_result);
                    bp = fmtInt(out[0..], bp, fspec, ival);
                } else {
                    const msg = std.fmt.allocPrint(std.heap.page_allocator, "printf: %{c}: invalid format\n", .{spec}) catch return last_result;
                    defer std.heap.page_allocator.free(msg);
                    core.writeAll(2, msg); last_result = 1; aborted = true; break;
                }
            } else {
                out[bp] = fmt[fi]; bp += 1; fi += 1;
            }
        }
        if (bp > 0) core.writeAll(1, out[0..bp]);
        if (aborted) break;
        if (ai == prev_ai and cycle > 0) break;
        cycle += 1;
    }

    return last_result;
}

fn isHex(c: u8) bool { return switch (c) { '0'...'9', 'a'...'f', 'A'...'F' => true, else => false }; }
fn hexVal(c: u8) u8 { return switch (c) { '0'...'9' => c - '0', 'a'...'f' => c - 'a' + 10, 'A'...'F' => c - 'A' + 10, else => 0 }; }

fn parseArgInt(arg: []const u8, err: *u8) i64 {
    if (arg.len > 0 and (arg[0] == '\'' or arg[0] == '"')) { return if (arg.len >= 2) @intCast(arg[1]) else 0; }
    const t = std.mem.trim(u8, arg, " \t");
    if (t.len == 0) return 0;
    if (std.mem.eql(u8, t, "-")) { core.writeAll(2, "printf: invalid number '-'\n"); err.* = 1; return 0; }
    var ok = true; var s: usize = 0; if (t[0] == '-' or t[0] == '+') s = 1;
    for (t[s..]) |c| { if (c < '0' or c > '9') { ok = false; break; } }
    if (!ok) {
        const msg = std.fmt.allocPrint(std.heap.page_allocator, "printf: invalid number '{s}'\n", .{t}) catch return 0;
        defer std.heap.page_allocator.free(msg);
        core.writeAll(2, msg); err.* = 1; return 0;
    }
    return std.fmt.parseInt(i64, t, 10) catch 0;
}

fn parseFloatArg(arg: []const u8, err: *u8) f64 {
    if (arg.len > 0 and (arg[0] == '\'' or arg[0] == '"')) { return if (arg.len >= 2) @floatFromInt(@as(i64, @intCast(arg[1]))) else 0; }
    const t = std.mem.trim(u8, arg, " \t");
    if (t.len == 0) return 0;
    // Handle leading '+' sign 
    var s = t;
    if (s.len > 0 and s[0] == '+') s = s[1..];
    // Handle leading '.' -> prepend "0"
    if (s.len > 0 and s[0] == '.') {
        var tmp: [64]u8 = undefined;
        const n = 1 + s.len;
        if (n > tmp.len) return 0;
        tmp[0] = '0';
        @memcpy(tmp[1..][0..s.len], s);
        const val = std.fmt.parseFloat(f64, tmp[0..n]) catch {
            err.* = 1; return 0;
        };
        return val;
    }
    return std.fmt.parseFloat(f64, s) catch {
        const iv = std.fmt.parseInt(i64, s, 10) catch {
            err.* = 1; return 0;
        };
        return @floatFromInt(iv);
    };
}

fn fmtSprintf(buf: []u8, bp: usize, fmt_spec: []const u8, arg: []const u8) usize {
    var zarg: [1024:0]u8 = undefined;
    const n = @min(arg.len, zarg.len - 1);
    @memcpy(zarg[0..n], arg[0..n]);
    zarg[n] = 0;
    var zfmt: [128:0]u8 = undefined;
    const m = @min(fmt_spec.len, zfmt.len - 1);
    @memcpy(zfmt[0..m], fmt_spec[0..m]);
    zfmt[m] = 0;
    var out: [2048]u8 = undefined;
    const r = core.c.snprintf(&out, out.len, &zfmt, &zarg);
    if (r < 0) return bp;
    const rn = @min(@as(usize, @intCast(r)), out.len - 1);
    if (bp + rn > buf.len) return bp;
    @memcpy(buf[bp..][0..rn], out[0..rn]);
    return bp + rn;
}

fn fmtInt(buf: []u8, bp: usize, fmt_spec: []const u8, val: i64) usize {
    var zfmt: [128:0]u8 = undefined;
    const m = @min(fmt_spec.len, zfmt.len - 1);
    @memcpy(zfmt[0..m], fmt_spec[0..m]);
    zfmt[m] = 0;
    var out: [2048]u8 = undefined;
    const r = core.c.snprintf(&out, out.len, &zfmt, val);
    if (r < 0) return bp;
    const rn = @min(@as(usize, @intCast(r)), out.len - 1);
    if (bp + rn > buf.len) return bp;
    @memcpy(buf[bp..][0..rn], out[0..rn]);
    return bp + rn;
}

fn fmtFloat(buf: []u8, bp: usize, fmt_spec: []const u8, val: f64) usize {
    var zfmt: [128:0]u8 = undefined;
    const m = @min(fmt_spec.len, zfmt.len - 1);
    @memcpy(zfmt[0..m], fmt_spec[0..m]);
    zfmt[m] = 0;
    var out: [2048]u8 = undefined;
    const r = core.c.snprintf(&out, out.len, &zfmt, val);
    if (r < 0) return bp;
    const rn = @min(@as(usize, @intCast(r)), out.len - 1);
    if (bp + rn > buf.len) return bp;
    @memcpy(buf[bp..][0..rn], out[0..rn]);
    return bp + rn;
}

fn fmtB(buf: []u8, bp: usize, arg: []const u8) usize {
    var dbuf: [4096]u8 = undefined;
    var dp: usize = 0;
    var i: usize = 0;
    while (i < arg.len and dp < dbuf.len) {
        if (arg[i] == '\\') {
            i += 1; if (i >= arg.len) break;
            switch (arg[i]) {
                '0'...'7' => { var v: u8 = 0; var n: usize = 0; while (i < arg.len and n < 3 and arg[i] >= '0' and arg[i] <= '7') : (n += 1) { v = v * 8 + (arg[i] - '0'); i += 1; } dbuf[dp] = v; dp += 1; },
                'x' => { i += 1; var v: u8 = 0; var n: usize = 0; while (i < arg.len and n < 2 and isHex(arg[i])) : (n += 1) { v = v * 16 + hexVal(arg[i]); i += 1; } dbuf[dp] = v; dp += 1; },
                '\\' => { dbuf[dp] = '\\'; dp += 1; i += 1; },
                'a' => { dbuf[dp] = 7; dp += 1; i += 1; },
                'b' => { dbuf[dp] = 8; dp += 1; i += 1; },
                'f' => { dbuf[dp] = 12; dp += 1; i += 1; },
                'n' => { dbuf[dp] = '\n'; dp += 1; i += 1; },
                'r' => { dbuf[dp] = '\r'; dp += 1; i += 1; },
                't' => { dbuf[dp] = '\t'; dp += 1; i += 1; },
                'v' => { dbuf[dp] = 11; dp += 1; i += 1; },
                'c' => { const db = dbuf[0..dp]; return fmtSprintf(buf, bp, "%s", db); },
                else => { dbuf[dp] = '\\'; dp += 1; if (dp < dbuf.len) { dbuf[dp] = arg[i]; dp += 1; } i += 1; },
            }
        } else {
            dbuf[dp] = arg[i]; dp += 1; i += 1;
        }
    }
    return fmtSprintf(buf, bp, "%s", dbuf[0..dp]);
}

fn fmtQ(buf: []u8, bp: usize, arg: []const u8) usize {
    var qbuf: [4096]u8 = undefined;
    var qp: usize = 0;
    qbuf[qp] = '\''; qp += 1;
    for (arg) |c| {
        switch (c) {
            '\'' => { const s = "'\\''"; const n = @min(s.len, qbuf.len - qp); @memcpy(qbuf[qp..][0..n], s[0..n]); qp += n; },
            '\\' => { qbuf[qp] = '\\'; qp += 1; if (qp < qbuf.len) { qbuf[qp] = '\\'; qp += 1; } },
            '\n' => { qbuf[qp] = '\\'; qp += 1; if (qp < qbuf.len) { qbuf[qp] = 'n'; qp += 1; } },
            '\r' => { qbuf[qp] = '\\'; qp += 1; if (qp < qbuf.len) { qbuf[qp] = 'r'; qp += 1; } },
            '\t' => { qbuf[qp] = '\\'; qp += 1; if (qp < qbuf.len) { qbuf[qp] = 't'; qp += 1; } },
            else => { qbuf[qp] = c; qp += 1; },
        }
    }
    qbuf[qp] = '\''; qp += 1;
    return fmtSprintf(buf, bp, "%s", qbuf[0..qp]);
}
