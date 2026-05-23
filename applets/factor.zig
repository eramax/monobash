const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "factor", .main = main };

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseU64(s: []const u8) ?u64 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
    if (i < s.len and s[i] == '+') i += 1;
    if (i >= s.len or !isDigit(s[i])) return null;
    var val: u64 = 0;
    while (i < s.len and isDigit(s[i])) : (i += 1) {
        val = val *% 10 +% @as(u64, s[i] - '0');
    }
    return val;
}

fn mulMod(a: u64, b: u64, m: u64) u64 {
    return @truncate((@as(u128, a) * @as(u128, b)) % @as(u128, m));
}

fn powMod(a: u64, d: u64, n: u64) u64 {
    var res: u64 = 1;
    var aa = a % n;
    var dd = d;
    while (dd > 0) {
        if (dd & 1 == 1) res = mulMod(res, aa, n);
        dd >>= 1;
        aa = mulMod(aa, aa, n);
    }
    return res;
}

fn isCompositeMR(n: u64, a: u64, d: u64, s: usize) bool {
    var x = powMod(a, d, n);
    if (x == 1 or x == n - 1) return false;
    var i: usize = 1;
    while (i < s) : (i += 1) {
        x = mulMod(x, x, n);
        if (x == n - 1) return false;
    }
    return true;
}

fn isPrime(n: u64) bool {
    if (n < 2) return false;
    if (n % 2 == 0) return n == 2;
    if (n % 3 == 0) return n == 3;
    if (n % 5 == 0) return n == 5;
    if (n % 7 == 0) return n == 7;
    if (n % 11 == 0) return n == 11;
    if (n % 13 == 0) return n == 13;
    if (n % 17 == 0) return n == 17;
    if (n % 19 == 0) return n == 19;
    if (n % 23 == 0) return n == 23;
    if (n < 29 * 29) return true;

    var d = n - 1;
    var s: usize = 0;
    while (d % 2 == 0) {
        d /= 2;
        s += 1;
    }

    const bases: [12]u64 = .{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37 };
    for (bases) |a| {
        if (a >= n) break;
        if (isCompositeMR(n, a, d, s)) return false;
    }
    return true;
}

fn gcd(a: u64, b: u64) u64 {
    if (b == 0) return a;
    return gcd(b, a % b);
}

fn pollardRho(n: u64) u64 {
    if (n % 2 == 0) return 2;
    if (n % 3 == 0) return 3;

    var x: u64 = 2;
    var y: u64 = 2;
    var d: u64 = 1;
    var c: u64 = 1;

    var iter: u64 = 0;
    while (d == 1 and iter < 1000000) : (iter += 1) {
        x = (mulMod(x, x, n) +% c) % n;
        y = (mulMod(y, y, n) +% c) % n;
        y = (mulMod(y, y, n) +% c) % n;
        d = gcd(if (x > y) x - y else y - x, n);
        if (d == n) {
            c += 1;
            x = 2;
            y = 2;
            d = 1;
            iter = 0;
        }
    }
    return d;
}

fn trialDivide(m: *u64, p: u64, factors: *[64]u64, count: *usize) void {
    while (m.* % p == 0) {
        factors[count.*] = p;
        count.* += 1;
        m.* /= p;
    }
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "factor: missing operand\n", .{});

    var buf: [4096]u8 = undefined;
    var any_err = false;

    for (args[1..]) |arg| {
        const n = parseU64(arg) orelse {
            core.eprint("factor: '{s}' is not a valid positive integer\n", .{arg});
            any_err = true;
            continue;
        };

        var pos: usize = 0;
        const num_str = std.fmt.bufPrint(buf[0..], "{d}", .{n}) catch "";
        pos = num_str.len;
        buf[pos] = ':'; pos += 1;

        if (n > 1) {
            var factors: [64]u64 = undefined;
            var count: usize = 0;
            var m = n;

            inline for (.{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97 }) |p| {
                trialDivide(&m, p, &factors, &count);
            }

            var p: u64 = 101;
            while (p * p <= m and p <= 1000) : (p += 2) {
                trialDivide(&m, p, &factors, &count);
            }

            while (m > 1 and !isPrime(m)) {
                const f = pollardRho(m);
                if (f <= 1 or f >= m) continue;
                trialDivide(&m, f, &factors, &count);
            }

            if (m > 1) {
                factors[count] = m;
                count += 1;
            }

            std.sort.insertion(u64, factors[0..count], {}, std.sort.asc(u64));
            for (factors[0..count]) |factor| {
                const s = std.fmt.bufPrint(buf[pos..], " {d}", .{factor}) catch "";
                pos += s.len;
            }
        }

        buf[pos] = '\n'; pos += 1;
        core.writeAll(1, buf[0..pos]);
    }

    return if (any_err) 1 else 0;
}
