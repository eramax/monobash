const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dc", .main = main };

const Allocator = std.mem.Allocator;
const AList = std.ArrayListAligned;

// ─── Big decimal ───
// digits LE: digits[0]=10^0 place; value = sum(digits[i]*10^i) * 10^(-scale)

const Big = struct {
    d: AList(u8, null) = .empty,
    s: u32 = 0,
    n: bool = false,

    fn free(b: *const Big, a: Allocator) void {
        @constCast(b).d.deinit(a);
    }

    fn dup(b: *const Big, a: Allocator) !Big {
        return Big{ .d = try b.d.clone(a), .s = b.s, .n = b.n };
    }

    fn zero() Big {
        return Big{};
    }

    fn isZero(b: *const Big) bool {
        return b.d.items.len == 0 or (b.d.items.len == 1 and b.d.items[0] == 0);
    }

    fn fromStr(s: []const u8) !Big {
        var r = Big{};
        var i: usize = 0;
        if (i < s.len and (s[i] == '_' or s[i] == '-')) { r.n = true; i += 1; }
        var dot = false;
        var fdig: u32 = 0; // digits after decimal point in the input
        var all_digits_before_dot: u32 = 0;
        var buf: AList(u8, null) = .empty;
        defer buf.deinit(std.heap.page_allocator);
        while (i < s.len) {
            const c = s[i];
            if (c == '.') { if (dot) return error.Invalid; dot = true; i += 1; continue; }
            if (c >= '0' and c <= '9') {
                buf.append(std.heap.page_allocator, c - '0') catch {};
                if (dot) fdig += 1 else all_digits_before_dot += 1;
                i += 1;
            } else break;
        }
        if (buf.items.len == 0) return error.Invalid;
        // Strip leading zeros from integer part
        var j: usize = 0;
        var int_zeros: u32 = 0;
        while (j < all_digits_before_dot and j < buf.items.len and buf.items[j] == 0) {
            j += 1;
            int_zeros += 1;
        }
        var k: usize = buf.items.len;
        while (k > j) {
            k -= 1;
            r.d.append(std.heap.page_allocator, buf.items[k]) catch {};
        }
        r.s = fdig;
        r.trim();
        return r;
    }

    fn fromU64(v: u64, a: Allocator) !Big {
        var r = Big{};
        if (v == 0) { try r.d.append(a, 0); return r; }
        var x = v;
        while (x > 0) {
            try r.d.append(a, @intCast(x % 10));
            x /= 10;
        }
        return r;
    }

    const PRINT_WIDTH: usize = 70;

    fn toStr(b: *const Big, a: Allocator) ![]u8 {
        var r: AList(u8, null) = .empty;
        errdefer r.deinit(a);
        if (b.n and !b.isZero()) try r.append(a, '-');
        var printed_int = false;
        var k: usize = b.d.items.len;
        while (k > b.s) {
            k -= 1;
            try r.append(a, @intCast(b.d.items[k] + '0'));
            printed_int = true;
        }
        if (!printed_int) try r.append(a, '0');

        if (b.s > 0) {
            try r.append(a, '.');
            var j: usize = b.s;
            while (j > 0) {
                j -= 1;
                const digit = if (j < b.d.items.len) b.d.items[j] else 0;
                try r.append(a, @intCast(digit + '0'));
            }
        }
        return r.toOwnedSlice(a);
    }

    fn toStrWrapped(b: *const Big, a: Allocator) ![]u8 {
        const raw = try b.toStr(a);
        if (raw.len <= PRINT_WIDTH) return raw;
        a.free(raw);
        var r: AList(u8, null) = .empty;
        errdefer r.deinit(a);
        var pos: usize = 0;
        while (pos < raw.len) {
            const end = @min(pos + PRINT_WIDTH, raw.len);
            if (pos + PRINT_WIDTH < raw.len) {
                r.appendSlice(a, raw[pos..end]) catch {};
                r.appendSlice(a, "\\\n") catch {};
            } else {
                r.appendSlice(a, raw[pos..end]) catch {};
            }
            pos = end;
        }
        return r.toOwnedSlice(a);
    }

    fn toI64(b: *const Big) i64 {
        var v: i64 = 0;
        var i: usize = b.d.items.len;
        while (i > b.s) {
            i -= 1;
            v = v * 10 + b.d.items[i];
        }
        if (b.n) v = -v;
        return v;
    }

    fn trim(b: *Big) void {
        while (b.d.items.len > 1 and b.d.items[b.d.items.len - 1] == 0) b.d.items.len -= 1;
        if (b.isZero()) b.n = false;
    }

    fn setScale(b: *Big, ns: u32, a: Allocator) void {
        if (ns == b.s) return;
        if (ns > b.s) {
            var i: u32 = 0;
            while (i < ns - b.s) {
                b.d.insert(a, 0, 0) catch {};
                i += 1;
            }
            b.s = ns;
        } else {
            var i: u32 = 0;
            while (i < b.s - ns) {
                if (b.d.items.len > 0) {
                    std.mem.copyForwards(u8, b.d.items[0..], b.d.items[1..]);
                    b.d.items.len -= 1;
                }
                i += 1;
            }
            b.s = ns;
        }
        b.trim();
    }

    fn cmpAbs(a: *const Big, b: *const Big) i8 {
        const ai = if (a.d.items.len > a.s) a.d.items.len - a.s else 0;
        const bi = if (b.d.items.len > b.s) b.d.items.len - b.s else 0;
        if (ai != bi) return if (ai > bi) 1 else -1;
        var i: usize = a.d.items.len;
        var j: usize = b.d.items.len;
        while (i > a.s and j > b.s) {
            i -= 1;
            j -= 1;
            if (a.d.items[i] != b.d.items[j]) return if (a.d.items[i] > b.d.items[j]) 1 else -1;
        }
        while (i > 0 or j > 0) {
            const ad = if (i > 0) blk: { i -= 1; break :blk a.d.items[i]; } else 0;
            const bd = if (j > 0) blk: { j -= 1; break :blk b.d.items[j]; } else 0;
            if (ad != bd) return if (ad > bd) 1 else -1;
        }
        return 0;
    }

    fn cmp(a: *const Big, b: *const Big) i8 {
        if (a.n != b.n) return if (a.n) -1 else 1;
        const r = cmpAbs(a, b);
        return if (a.n) @as(i8, -r) else r;
    }
};

fn alignScale(a: *Big, b: *Big, al: Allocator) void {
    if (a.s < b.s) a.setScale(b.s, al) else if (b.s < a.s) b.setScale(a.s, al);
}

fn addAbs(a: *const Big, b: *const Big, al: Allocator) !Big {
    var r = Big{};
    const ms = @max(a.s, b.s);
    const alen = a.d.items.len;
    const blen = b.d.items.len;
    const mlen = @max(alen, blen) + 1;
    try r.d.ensureTotalCapacity(al, mlen);
    var c: u8 = 0;
    var i: usize = 0;
    while (i < mlen - 1) {
        const ad = if (i < alen) a.d.items[i] else 0;
        const bd = if (i < blen) b.d.items[i] else 0;
        var s: u8 = ad + bd + c;
        if (s >= 10) { s -= 10; c = 1; } else c = 0;
        r.d.appendAssumeCapacity(s);
        i += 1;
    }
    if (c > 0) r.d.appendAssumeCapacity(c);
    r.s = ms;
    return r;
}

fn subAbs(a: *const Big, b: *const Big, al: Allocator) !Big {
    var r = Big{};
    const ms = @max(a.s, b.s);
    const alen = a.d.items.len;
    const blen = b.d.items.len;
    const mlen = @max(alen, blen);
    try r.d.ensureTotalCapacity(al, mlen);
    var br: u8 = 0;
    var i: usize = 0;
    while (i < mlen) {
        const ad = if (i < alen) a.d.items[i] else 0;
        const bd = if (i < blen) b.d.items[i] else 0;
        var d: i32 = @as(i32, ad) - @as(i32, bd) - @as(i32, br);
        if (d < 0) { d += 10; br = 1; } else br = 0;
        r.d.appendAssumeCapacity(@intCast(d));
        i += 1;
    }
    r.s = ms;
    return r;
}

fn addSigned(a: *const Big, b: *const Big, al: Allocator) !Big {
    var ac = try a.dup(al);
    defer ac.free(al);
    var bc = try b.dup(al);
    defer bc.free(al);
    alignScale(&ac, &bc, al);
    if (ac.n == bc.n) {
        var r = try addAbs(&ac, &bc, al);
        r.n = ac.n;
        r.trim();
        return r;
    }
    const ca = Big.cmpAbs(&ac, &bc);
    if (ca == 0) return Big{};
    const a_gt = ca > 0;
    var r = try subAbs(if (a_gt) &ac else &bc, if (a_gt) &bc else &ac, al);
    r.n = if (a_gt) ac.n else bc.n;
    r.trim();
    return r;
}

fn mulBig(a: *const Big, b: *const Big, al: Allocator) !Big {
    if (a.isZero() or b.isZero()) return Big{};
    const alen = a.d.items.len;
    const blen = b.d.items.len;
    var tmp = try al.alloc(u16, alen + blen);
    defer al.free(tmp);
    @memset(tmp, 0);
    for (0..alen) |i| {
        var c: u16 = 0;
        for (0..blen) |j| {
            const idx = i + j;
            const p = @as(u16, a.d.items[i]) * @as(u16, b.d.items[j]) + tmp[idx] + c;
            tmp[idx] = @intCast(p % 10);
            c = p / 10;
        }
        if (c > 0) tmp[i + blen] += c;
    }
    var r = Big{};
    var i: usize = 0;
    while (i < alen + blen) {
        r.d.append(al, @intCast(tmp[i])) catch {};
        i += 1;
    }
    r.s = a.s + b.s;
    r.n = a.n != b.n;
    r.trim();
    return r;
}

fn divBig(a: *const Big, b: *const Big, scale: u32, al: Allocator) !Big {
    if (b.isZero()) return error.DivByZero;
    if (a.isZero()) {
        var n = Big{};
        n.s = scale;
        return n;
    }

    // Convert to integers by aligning scales
    var ac = try a.dup(al);
    defer ac.free(al);
    var bc = try b.dup(al);
    defer bc.free(al);
    alignScale(&ac, &bc, al);

    // Add precision digits (no extra for rounding - truncate toward zero)
    var i: u32 = 0;
    while (i < scale) {
        ac.d.insert(al, 0, 0) catch {};
        ac.s += 1;
        i += 1;
    }

    // Now ac and bc have same scale; remove scale for integer division
    const res_scale = ac.s;
    ac.s = 0;
    bc.s = 0;
    bc.trim();
    if (bc.isZero()) return error.DivByZero;

    // Long division: compute ac / bc (both integers)
    // We work with the MSB of the dividend and build quotient digit by digit
    var result = Big{};
    defer result.d.deinit(al);

    // Get digit arrays as []u8 slices, MSB first
    var adiv: AList(u8, null) = .empty;
    defer adiv.deinit(al);
    var k: usize = ac.d.items.len;
    while (k > 0) {
        k -= 1;
        adiv.append(al, ac.d.items[k]) catch {};
    }
    var bdiv: AList(u8, null) = .empty;
    defer bdiv.deinit(al);
    k = bc.d.items.len;
    while (k > 0) {
        k -= 1;
        bdiv.append(al, bc.d.items[k]) catch {};
    }

    if (bdiv.items.len == 0) return error.DivByZero;

    // Long division
    var rem: AList(u8, null) = .empty;
    defer rem.deinit(al);

    var qi: usize = 0;
    while (qi < adiv.items.len) {
        // Bring down next digit
        rem.append(al, adiv.items[qi]) catch {};

        // Remove leading zeros from rem
        while (rem.items.len > 1 and rem.items[0] == 0) {
            std.mem.copyForwards(u8, rem.items[0..], rem.items[1..]);
            rem.items.len -= 1;
        }

        // Compare with divisor
        var qd: u8 = 0;
        while (rem.items.len >= bdiv.items.len) {
            // Check if rem >= bdiv
            var gt = false;
            if (rem.items.len > bdiv.items.len) {
                gt = true;
            } else {
                // Same length, compare digit by digit
                var di: usize = 0;
                while (di < rem.items.len) {
                    if (rem.items[di] > bdiv.items[di]) { gt = true; break; }
                    if (rem.items[di] < bdiv.items[di]) break;
                    di += 1;
                }
                if (di == rem.items.len) gt = true; // equal
            }

            if (!gt) break;

            // Subtract bdiv from rem
            var borrow: i32 = 0;
            var ri: usize = rem.items.len;
            var bj: usize = bdiv.items.len;
            while (bj > 0) {
                ri -= 1;
                bj -= 1;
                var diff = @as(i32, rem.items[ri]) - @as(i32, bdiv.items[bj]) - borrow;
                if (diff < 0) { diff += 10; borrow = 1; } else borrow = 0;
                rem.items[ri] = @intCast(diff);
            }
            while (ri > 0 and borrow > 0) {
                ri -= 1;
                var diff = @as(i32, rem.items[ri]) - borrow;
                if (diff < 0) { diff += 10; borrow = 1; } else borrow = 0;
                rem.items[ri] = @intCast(diff);
            }

            // Remove leading zeros from rem
            while (rem.items.len > 1 and rem.items[0] == 0) {
                std.mem.copyForwards(u8, rem.items[0..], rem.items[1..]);
                rem.items.len -= 1;
            }

            qd += 1;
        }

        result.d.append(al, qd) catch {};
        qi += 1;
    }

    // Convert result from MSB-first (in result.d) to LSB-first (in final result)
    var final_r = Big{};
    k = result.d.items.len;
    while (k > 0) {
        k -= 1;
        final_r.d.append(al, result.d.items[k]) catch {};
    }
    final_r.s = res_scale;
    final_r.n = a.n != b.n;
    final_r.trim();
    return final_r;
}

// ─── V: stack value ───

const VTag = enum { num, str };
const V = struct {
    t: VTag,
    n: Big,
    s: []const u8,
};

const VL = AList(V, null);

// ─── State ───

const Empty = VL.empty;

const St = struct {
    a: Allocator,
    stk: VL = .empty,
    reg: [256]VL,
    rsta: [256]VL,
    prec: u32 = 0,
    obase: u8 = 10,
    ibase: u8 = 10,
};

fn freeV(v: *V, a: Allocator) void {
    switch (v.t) {
        .num => v.n.free(a),
        .str => if (v.s.len > 0) a.free(v.s),
    }
}

// ─── Entry point ───

pub fn main(args: [][]const u8) u8 {
    const a = std.heap.page_allocator;
    var st = St{
        .a = a,
        .reg = [_]VL{Empty} ** 256,
        .rsta = [_]VL{Empty} ** 256,
    };
    defer {
        for (st.stk.items) |*v| freeV(v, a);
        st.stk.deinit(a);
        for (0..256) |j| { st.reg[j].deinit(a); st.rsta[j].deinit(a); }
    }

    var fi: usize = 1;
    var hasf = false;
    var hase = false;

    while (fi < args.len) {
        const arg = args[fi];
        if (std.mem.startsWith(u8, arg, "-e")) {
            hase = true;
            const expr = if (arg.len > 2) arg[2..] else if (fi + 1 < args.len) blk: { fi += 1; break :blk args[fi]; } else {
                return core.die(1, "dc: -e requires argument\n", .{});
            };
            exec(&st, expr);
        } else if (std.mem.startsWith(u8, arg, "-f")) {
            hasf = true;
            const fname = if (arg.len > 2) arg[2..] else if (fi + 1 < args.len) blk: { fi += 1; break :blk args[fi]; } else {
                return core.die(1, "dc: -f requires argument\n", .{});
            };
            const fd = core.openReadName(fname) orelse
                return core.die(1, "dc: cannot open '{s}'\n", .{fname});
            defer _ = core.c.close(fd);
            procFile(&st, fd);
        } else if (arg.len > 0 and arg[0] == '-') {
            fi += 1; continue;
        } else {
            hasf = true;
            const fd = core.openReadName(arg) orelse
                return core.die(1, "dc: cannot open '{s}'\n", .{arg});
            defer _ = core.c.close(fd);
            procFile(&st, fd);
        }
        fi += 1;
    }

    if (!hasf and !hase) procFile(&st, 0);
    return 0;
}

fn procFile(st: *St, fd: c_int) void {
    var rd = core.LineReader.init(fd);
    while (rd.next()) |line| {
        exec(st, line);
    }
}

fn pushN(st: *St, n: Big) void {
    st.stk.append(st.a, V{ .t = .num, .n = n, .s = "" }) catch {};
}

fn pushS(st: *St, s: []const u8) void {
    st.stk.append(st.a, V{ .t = .str, .n = undefined, .s = s }) catch {};
}

fn popV(st: *St) ?V {
    return st.stk.pop();
}

fn popN(st: *St) ?Big {
    var v = st.stk.pop() orelse {
        core.writeAll(2, "dc: stack empty\n");
        return null;
    };
    if (v.t != .num) {
        core.writeAll(2, "dc: not a number\n");
        freeV(&v, st.a);
        return null;
    }
    return v.n;
}

fn pN(st: *St, n: *const Big) void {
    const s = n.toStrWrapped(st.a) catch {
        core.writeAll(2, "dc: out of memory\n");
        return;
    };
    defer st.a.free(s);
    core.writeAll(1, s);
}

fn exec(st: *St, line: []const u8) void {
    const a = st.a;
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        // Skip whitespace
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') { i += 1; continue; }
        if (c == '#') return;

        // String literal [...]
        if (c == '[') {
            var dep: u32 = 1;
            var j = i + 1;
            while (j < line.len and dep > 0) {
                if (line[j] == '[') { dep += 1; }
                if (line[j] == ']') { dep -= 1; }
                if (line[j] == '\\' and j + 1 < line.len) { j += 1; }
                j += 1;
            }
            if (dep != 0) { core.writeAll(2, "dc: unterminated string\n"); return; }
            const raw = line[i + 1 .. j - 1];
            var buf: AList(u8, null) = .empty;
            defer buf.deinit(a);
            var k: usize = 0;
            while (k < raw.len) {
                if (raw[k] == '\\' and k + 1 < raw.len) {
                    const next = raw[k + 1];
                    if (next == '[' or next == ']') { k += 1; buf.append(a, next) catch {}; }
                    else { buf.append(a, '\\') catch {}; buf.append(a, next) catch {}; k += 1; }
                } else { buf.append(a, raw[k]) catch {}; }
                k += 1;
            }
            const owned = buf.toOwnedSlice(a) catch { core.writeAll(2, "dc: out of memory\n"); return; };
            pushS(st, owned);
            i = j;
            continue;
        }

        // Number (including _ for negative)
        if ((c >= '0' and c <= '9') or c == '_' or c == '.') {
            var j = i;
            var dot = false;
            if (c == '_') { j += 1; }
            while (j < line.len) {
                const ch = line[j];
                if (ch >= '0' and ch <= '9') { j += 1; continue; }
                if (ch == '.' and !dot) { dot = true; j += 1; continue; }
                break;
            }
            if (j > i) {
                const n = Big.fromStr(line[i..j]) catch { i = j; continue; };
                pushN(st, n);
                i = j;
                continue;
            }
        }

        // sX, lX, SX, LX (register operations)
        if ((c == 's' or c == 'l' or c == 'S' or c == 'L') and i + 1 < line.len) {
            const reg = line[i + 1];
            i += 2;
            switch (c) {
                's' => {
                    const v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                    // Clear existing register
                    var rlst = &st.reg[reg];
                    for (rlst.items) |*rv| freeV(rv, a);
                    rlst.deinit(a);
                    rlst.* = .empty;
                    rlst.append(a, v) catch {};
                },
                'l' => {
                    if (st.reg[reg].items.len == 0) { core.writeAll(2, "dc: register empty\n"); continue; }
                    const ref = &st.reg[reg].getLast();
                    const nc = switch (ref.t) {
                        .num => V{ .t = .num, .n = ref.n.dup(a) catch { continue; }, .s = "" },
                        .str => V{ .t = .str, .n = undefined, .s = a.dupe(u8, ref.s) catch { continue; } },
                    };
                    st.stk.append(a, nc) catch {};
                },
                'S' => {
                    const v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                    st.rsta[reg].append(a, v) catch {};
                },
                'L' => {
                    const v = st.rsta[reg].pop() orelse { core.writeAll(2, "dc: register stack empty\n"); continue; };
                    st.stk.append(a, v) catch {};
                },
                else => {},
            }
            continue;
        }

        // Conditionals: =X, <X, >X, =XeY, <XeY, >XeY
        if ((c == '=' or c == '<' or c == '>') and i + 1 < line.len) {
            const cond = c;
            const reg = line[i + 1];
            i += 2;
            var have_else = false;
            var ereg: u8 = 0;
            if (i < line.len and line[i] == 'e' and i + 1 < line.len) {
                have_else = true;
                ereg = line[i + 1];
                i += 2;
            }
            var b = popN(st) orelse continue;
            defer b.free(a);
            var aa = popN(st) orelse continue;
            defer aa.free(a);
            var ac = aa;
            var bc = b;
            const ca = Big.cmpAbs(&ac, &bc);
            var exec_target = false;
            if (cond == '=' and ca == 0) exec_target = true;
            if (cond == '<' and ca < 0) exec_target = true;
            if (cond == '>' and ca > 0) exec_target = true;

            if (exec_target) {
                if (st.reg[reg].items.len > 0 and st.reg[reg].getLast().t == .str) {
                    exec(st, st.reg[reg].getLast().s);
                }
            } else if (have_else) {
                if (st.reg[ereg].items.len > 0 and st.reg[ereg].getLast().t == .str) {
                    exec(st, st.reg[ereg].getLast().s);
                }
            }
            continue;
        }

        i += 1;
        switch (c) {
            'p' => {
                if (st.stk.items.len == 0) { core.writeAll(2, "dc: stack empty\n"); continue; }
                const ref = &st.stk.getLast();
                switch (ref.t) {
                    .num => { pN(st, &ref.n); core.writeAll(1, "\n"); },
                    .str => { core.writeAll(1, ref.s); core.writeAll(1, "\n"); },
                }
            },
            'n' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                switch (v.t) {
                    .num => pN(st, &v.n),
                    .str => core.writeAll(1, v.s),
                }
                freeV(&v, a);
            },
            'P' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (v.t == .str) {
                    core.writeAll(1, v.s);
                } else {
                    var val = v.n.toI64();
                    var buf: [8]u8 = undefined;
                    var pos: usize = 0;
                    while (val > 0 and pos < 8) {
                        buf[pos] = @intCast(val & 0xFF);
                        val >>= 8;
                        pos += 1;
                    }
                    if (pos > 0) {
                        var k: usize = pos;
                        while (k > 0) {
                            k -= 1;
                            const ch: [1]u8 = @bitCast(buf[k]);
                            core.writeAll(1, &ch);
                        }
                    }
                }
                freeV(&v, a);
            },
            'f' => {
                var j: usize = st.stk.items.len;
                while (j > 0) {
                    j -= 1;
                    const ref = &st.stk.items[j];
                    switch (ref.t) {
                        .num => { pN(st, &ref.n); core.writeAll(1, "\n"); },
                        .str => { core.writeAll(1, ref.s); core.writeAll(1, "\n"); },
                    }
                }
            },
            'r' => {
                if (st.stk.items.len < 2) { core.writeAll(2, "dc: stack underflow\n"); continue; }
                const len = st.stk.items.len;
                std.mem.swap(V, &st.stk.items[len - 1], &st.stk.items[len - 2]);
            },
            'c' => {
                var j: usize = st.stk.items.len;
                while (j > 0) { j -= 1; freeV(&st.stk.items[j], a); }
                st.stk.deinit(a);
                st.stk = .empty;
            },
            'd' => {
                if (st.stk.items.len == 0) { core.writeAll(2, "dc: stack empty\n"); continue; }
                const ref = &st.stk.getLast();
                const nc = switch (ref.t) {
                    .num => V{ .t = .num, .n = ref.n.dup(a) catch { continue; }, .s = "" },
                    .str => V{ .t = .str, .n = undefined, .s = a.dupe(u8, ref.s) catch { continue; } },
                };
                st.stk.append(a, nc) catch {};
            },
            'z' => {
                const n = Big.fromU64(@intCast(st.stk.items.len), a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },
            'R' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                freeV(&v, a);
            },

            // Arithmetic
            '+' => {
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                const r = addSigned(&aa.n, &b.n, a) catch { b.n.free(a); aa.n.free(a); core.writeAll(2, "dc: out of memory\n"); continue; };
                b.n.free(a);
                aa.n.free(a);
                pushN(st, r);
            },
            '-' => {
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var bb = b.n;
                bb.n = !bb.n;
                const r = addSigned(&aa.n, &bb, a) catch { aa.n.free(a); bb.free(a); core.writeAll(2, "dc: out of memory\n"); continue; };
                aa.n.free(a);
                pushN(st, r);
            },
            '*' => {
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var r = mulBig(&aa.n, &b.n, a) catch { aa.n.free(a); b.n.free(a); core.writeAll(2, "dc: out of memory\n"); continue; };
                aa.n.free(a);
                b.n.free(a);
                if (r.s > st.prec) r.setScale(st.prec, a);
                pushN(st, r);
            },
            '/' => {
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                const r = divBig(&aa.n, &b.n, st.prec, a) catch {
                    aa.n.free(a); b.n.free(a);
                    if (@errorReturnTrace()) |_| {} // consume error
                    core.writeAll(2, "dc: divide by zero\n");
                    continue;
                };
                aa.n.free(a);
                b.n.free(a);
                pushN(st, r);
            },
            '%' => {
                // a % b = a - (a/b)*b
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                const ca = Big.cmpAbs(&aa.n, &b.n);
                defer { aa.n.free(a); b.n.free(a); }
                if (ca == 0) {
                    pushN(st, Big{});
                    continue;
                }
                // q = trunc(a / b) toward zero
                // r = a - q * b
                var div = divBig(&aa.n, &b.n, 0, a) catch {
                    core.writeAll(2, "dc: divide by zero\n"); continue;
                };
                defer div.free(a);
                var prod = mulBig(&div, &b.n, a) catch { continue; };
                defer prod.free(a);
                var prod2 = prod;
                prod2.n = !prod2.n;
                const res = addSigned(&aa.n, &prod2, a) catch { continue; };
                pushN(st, res);
            },
            '^' => {
                var exp = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (exp.t != .num) { freeV(&exp, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var base = st.stk.pop() orelse { exp.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (base.t != .num) { exp.n.free(a); freeV(&base, a); core.writeAll(2, "dc: not a number\n"); continue; }
                const exp_val = exp.n.toI64();
                defer { base.n.free(a); exp.n.free(a); }
                if (exp_val < 0) {
                    // For negative exponent, compute positive power then divide 1 by it
                    var pow = -exp_val;
                    var result = Big.fromU64(1, a) catch { continue; };
                    defer result.free(a);
                    var factor = base.n.dup(a) catch { continue; };
                    defer factor.free(a);
                    while (pow > 0) {
                        if (pow & 1 == 1) {
                            const new = mulBig(&result, &factor, a) catch { continue; };
                            result.free(a);
                            result = new;
                        }
                        pow >>= 1;
                        if (pow > 0) {
                            const new = mulBig(&factor, &factor, a) catch { continue; };
                            factor.free(a);
                            factor = new;
                        }
                    }
                    // 1 / result
                    var one = Big.fromU64(1, a) catch { continue; };
                    defer one.free(a);
                    var inv = divBig(&one, &result, st.prec, a) catch { continue; };
                    defer inv.free(a);
                    const r2 = inv.dup(a) catch { continue; };
                    pushN(st, r2);
                    continue;
                }
                var result = Big.fromU64(1, a) catch { continue; };
                defer result.free(a);
                var power = exp_val;
                var factor = base.n.dup(a) catch { continue; };
                defer factor.free(a);
                while (power > 0) {
                    if (power & 1 == 1) {
                        const new = mulBig(&result, &factor, a) catch { continue; };
                        result.free(a);
                        result = new;
                    }
                    power >>= 1;
                    if (power > 0) {
                        const new = mulBig(&factor, &factor, a) catch { continue; };
                        factor.free(a);
                        factor = new;
                    }
                }
                const r = result.dup(a) catch { continue; };
                pushN(st, r);
            },
            '~' => {
                // Divmod: push remainder then quotient
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var div = divBig(&aa.n, &b.n, st.prec, a) catch {
                    aa.n.free(a); b.n.free(a);
                    core.writeAll(2, "dc: divide by zero\n"); continue;
                };
                defer div.free(a);
                var prod = mulBig(&div, &b.n, a) catch { aa.n.free(a); b.n.free(a); continue; };
                defer prod.free(a);
                var prod2 = prod;
                prod2.n = !prod2.n;
                const rem = addSigned(&aa.n, &prod2, a) catch { aa.n.free(a); b.n.free(a); continue; };
                aa.n.free(a);
                b.n.free(a);
                pushN(st, rem);
                const d2 = div.dup(a) catch { continue; };
                pushN(st, d2);
            },
            '|' => {
                // Modular exponentiation: base exp mod
                var mod = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (mod.t != .num) { freeV(&mod, a); core.writeAll(2, "dc: not a number\n"); continue; }
                var exp = st.stk.pop() orelse { mod.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (exp.t != .num) { freeV(&exp, a); mod.n.free(a); core.writeAll(2, "dc: not a number\n"); continue; }
                var base = st.stk.pop() orelse { mod.n.free(a); exp.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (base.t != .num) { freeV(&base, a); mod.n.free(a); exp.n.free(a); core.writeAll(2, "dc: not a number\n"); continue; }
                const exp_val = exp.n.toI64();
                defer { base.n.free(a); exp.n.free(a); mod.n.free(a); }
                var result = Big.fromU64(1, a) catch { continue; };
                defer result.free(a);
                var power = exp_val;
                var factor = base.n.dup(a) catch { continue; };
                defer factor.free(a);
                while (power > 0) {
                    if (power & 1 == 1) {
                        const new = mulBig(&result, &factor, a) catch { continue; };
                        result.free(a);
                        result = new;
                        // mod
                        var m = divBig(&result, &mod.n, 0, a) catch { continue; };
                        defer m.free(a);
                        var prod = mulBig(&m, &mod.n, a) catch { continue; };
                        defer prod.free(a);
                        prod.n = !prod.n;
                        const rem = addSigned(&result, &prod, a) catch { continue; };
                        result.free(a);
                        result = rem;
                        result.trim();
                    }
                    power >>= 1;
                    if (power > 0) {
                        const new = mulBig(&factor, &factor, a) catch { continue; };
                        factor.free(a);
                        factor = new;
                        // mod
                        var m = divBig(&factor, &mod.n, 0, a) catch { continue; };
                        defer m.free(a);
                        var prod = mulBig(&m, &mod.n, a) catch { continue; };
                        defer prod.free(a);
                        prod.n = !prod.n;
                        const rem = addSigned(&factor, &prod, a) catch { continue; };
                        factor.free(a);
                        factor = rem;
                        factor.trim();
                    }
                }
                const r = result.dup(a) catch { continue; };
                pushN(st, r);
            },
            'v' => {
                var n = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (n.t != .num) { freeV(&n, a); core.writeAll(2, "dc: not a number\n"); continue; }
                defer n.n.free(a);
                // sqrt using Newton's method
                if (n.n.isZero()) { pushN(st, Big{}); continue; }
                if (n.n.n) { core.writeAll(2, "dc: sqrt of negative\n"); continue; }
                // x_{n+1} = (x_n + a/x_n) / 2
                var guess = n.n.dup(a) catch { continue; };
                defer guess.free(a);
                // Initial guess: sqrt(a) ~ a / (10^(digits/2))
                // Simple: use a as starting guess
                const prec = @max(st.prec, n.n.s * 2);
                var iter: u32 = 0;
                while (iter < 100) {
                    var div = divBig(&n.n, &guess, prec, a) catch { continue; };
                    defer div.free(a);
                    var sum = addSigned(&guess, &div, a) catch { continue; };
                    defer sum.free(a);
                    // divide by 2
                    var two = Big.fromU64(2, a) catch { continue; };
                    defer two.free(a);
                    var new_guess = divBig(&sum, &two, prec, a) catch { continue; };
                    defer new_guess.free(a);
                    const diff = Big.cmpAbs(&new_guess, &guess);
                    guess.free(a);
                    guess = new_guess;
                    if (diff == 0) break;
                    iter += 1;
                }
                if (guess.s > st.prec) guess.setScale(st.prec, a);
                guess.trim();
                const r = guess.dup(a) catch { continue; };
                pushN(st, r);
            },

            'o' => {
                var n = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (n.t != .num) { freeV(&n, a); continue; }
                st.obase = @intCast(n.n.toI64());
                n.n.free(a);
            },
            'i' => {
                var n = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (n.t != .num) { freeV(&n, a); continue; }
                st.ibase = @intCast(n.n.toI64());
                n.n.free(a);
            },
            'k' => {
                var n = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (n.t != .num) { freeV(&n, a); continue; }
                st.prec = @intCast(n.n.toI64());
                n.n.free(a);
            },
            'O' => {
                const n = Big.fromU64(st.obase, a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },
            'I' => {
                const n = Big.fromU64(st.ibase, a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },
            'K' => {
                const n = Big.fromU64(st.prec, a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },
            'Z' => {
                if (st.stk.items.len == 0) { core.writeAll(2, "dc: stack empty\n"); continue; }
                const ref = &st.stk.getLast();
                const len = switch (ref.t) {
                    .num => @as(u64, @intCast(ref.n.d.items.len)),
                    .str => @as(u64, @intCast(ref.s.len)),
                };
                const n = Big.fromU64(len, a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },
            'X' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (v.t != .num) { freeV(&v, a); continue; }
                const sc = Big.fromU64(v.n.s, a) catch { v.n.free(a); core.writeAll(2, "dc: out of memory\n"); continue; };
                v.n.free(a);
                pushN(st, sc);
            },

            'x' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (v.t == .str) {
                    const s = a.dupe(u8, v.s) catch { freeV(&v, a); continue; };
                    freeV(&v, a);
                    exec(st, s);
                    a.free(s);
                } else {
                    // x on number: push back
                    st.stk.append(a, v) catch {};
                }
            },
            '?' => {
                var rd = core.LineReader.init(0);
                if (rd.next()) |s| exec(st, s);
            },
            'a' => {
                var v = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                switch (v.t) {
                    .num => {
                        const val = v.n.toI64();
                        v.n.free(a);
                        const ch: u8 = @intCast(@as(u64, @intCast(val)) & 0xFF);
                        const s2 = a.dupe(u8, &[1]u8{ch}) catch { continue; };
                        pushS(st, s2);
                    },
                    .str => {
                        const ch = if (v.s.len > 0) @as(u64, v.s[0]) else 0;
                        const n = Big.fromU64(ch, a) catch { freeV(&v, a); continue; };
                        freeV(&v, a);
                        pushN(st, n);
                    },
                }
            },

            // Boolean comparisons (return 0/1)
            '(', '{', 'G', 'N', 'M' => {
                var b = st.stk.pop() orelse { core.writeAll(2, "dc: stack empty\n"); continue; };
                if (b.t != .num) { freeV(&b, a); continue; }
                var aa = st.stk.pop() orelse { b.n.free(a); core.writeAll(2, "dc: stack empty\n"); continue; };
                if (aa.t != .num) { b.n.free(a); freeV(&aa, a); continue; }
                const ca = Big.cmpAbs(&aa.n, &b.n);
                var r: u64 = 0;
                switch (c) {
                    '(' => r = if (ca < 0) 1 else 0,
                    '{' => r = if (ca <= 0) 1 else 0,
                    'G' => r = if (ca >= 0) 1 else 0,
                    'N' => r = if (ca != 0) 1 else 0,
                    'M' => r = if (ca > 0) 1 else 0,
                    else => {},
                }
                aa.n.free(a);
                b.n.free(a);
                const n = Big.fromU64(r, a) catch { core.writeAll(2, "dc: out of memory\n"); continue; };
                pushN(st, n);
            },

            else => {
                core.writeAll(2, "dc: unknown command\n");
            },
        }
    }
}
