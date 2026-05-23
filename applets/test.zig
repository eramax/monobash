const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "test", .main = main };

pub fn main(args: [][]const u8) u8 {
    const a = args[1..];
    if (a.len == 0) return 1;
    if (a.len == 1) return if (a[0].len > 0) 0 else 1;
    if (a.len == 2) {
        if (std.mem.eql(u8, a[0], "!")) {
            const r = testUnary(a[1]);
            return if (r == 0) 1 else 0;
        }
        return testUnaryOp(a[0], a[1]);
    }
    if (a.len == 3) {
        if (isBinaryOp(a[1])) return testBinary(a[0], a[1], a[2]);
        if (std.mem.eql(u8, a[0], "!")) {
            const r = testUnary(a[1]);
            return if (r == 0) 1 else 0;
        }
        if (std.mem.eql(u8, a[0], "(") and std.mem.eql(u8, a[2], ")"))
            return if (a[1].len > 0) 0 else 1;
    }
    if (a.len == 4 and std.mem.eql(u8, a[0], "!")) {
        const sub = a[1..];
        if (isBinaryOp(sub[1])) {
            const r = testBinary(sub[0], sub[1], sub[2]);
            return if (r == 0) 1 else 0;
        }
        if (std.mem.eql(u8, sub[0], "(") and std.mem.eql(u8, sub[2], ")")) {
            const r: u8 = if (sub[1].len > 0) 0 else 1;
            return if (r == 0) 1 else 0;
        }
    }
    var pos: usize = 0;
    return parseExpr(a, &pos);
}

fn isBinaryOp(s: []const u8) bool {
    return std.mem.eql(u8, s, "=") or std.mem.eql(u8, s, "==") or
        std.mem.eql(u8, s, "!=") or
        std.mem.eql(u8, s, "-eq") or std.mem.eql(u8, s, "-ne") or
        std.mem.eql(u8, s, "-lt") or std.mem.eql(u8, s, "-le") or
        std.mem.eql(u8, s, "-gt") or std.mem.eql(u8, s, "-ge");
}

fn isUnaryOp(s: []const u8) bool {
    if (s.len != 2 or s[0] != '-') return false;
    return switch (s[1]) {
        'z', 'n', 'f', 'd', 'e', 'r', 'w', 'x', 's', 'L', 'h', 'b', 'c', 'g', 'u', 'k', 'p', 't', 'O', 'G' => true,
        else => false,
    };
}

fn parseExpr(args: [][]const u8, pos: *usize) u8 {
    var result = parseTerm(args, pos);
    while (pos.* < args.len and std.mem.eql(u8, args[pos.*], "-o")) {
        pos.* += 1;
        const rhs = parseTerm(args, pos);
        result = if (result == 0 or rhs == 0) 0 else 1;
    }
    return result;
}

fn parseTerm(args: [][]const u8, pos: *usize) u8 {
    var result = parseFactor(args, pos);
    while (pos.* < args.len and std.mem.eql(u8, args[pos.*], "-a")) {
        pos.* += 1;
        const rhs = parseFactor(args, pos);
        result = if (result == 0 and rhs == 0) 0 else 1;
    }
    return result;
}

fn parseFactor(args: [][]const u8, pos: *usize) u8 {
    if (pos.* >= args.len) return 1;
    if (std.mem.eql(u8, args[pos.*], "!")) {
        if (pos.* + 1 < args.len and
            !std.mem.eql(u8, args[pos.* + 1], "-a") and
            !std.mem.eql(u8, args[pos.* + 1], "-o") and
            !std.mem.eql(u8, args[pos.* + 1], ")"))
        {
            pos.* += 1;
            const r = parseFactor(args, pos);
            return if (r == 0) 1 else 0;
        }
        return parsePrimary(args, pos);
    }
    if (std.mem.eql(u8, args[pos.*], "(")) {
        if (pos.* + 2 < args.len and isBinaryOp(args[pos.* + 1]))
            return parsePrimary(args, pos);
        pos.* += 1;
        const r = parseExpr(args, pos);
        if (pos.* >= args.len or !std.mem.eql(u8, args[pos.*], ")"))
            return 1;
        pos.* += 1;
        return r;
    }
    return parsePrimary(args, pos);
}

fn parsePrimary(args: [][]const u8, pos: *usize) u8 {
    if (pos.* + 2 < args.len and isBinaryOp(args[pos.* + 1])) {
        const r = testBinary(args[pos.*], args[pos.* + 1], args[pos.* + 2]);
        pos.* += 3;
        return r;
    }
    if (pos.* + 1 < args.len and isUnaryOp(args[pos.*])) {
        const r = testUnaryOp(args[pos.*], args[pos.* + 1]);
        pos.* += 2;
        return r;
    }
    const r: u8 = if (args[pos.*].len > 0) 0 else 1;
    pos.* += 1;
    return r;
}

fn testUnary(arg: []const u8) u8 {
    return if (arg.len > 0) 0 else 1;
}

fn testUnaryOp(op: []const u8, operand: []const u8) u8 {
    if (op.len != 2 or op[0] != '-') return 1;
    return switch (op[1]) {
        'z' => if (operand.len == 0) 0 else 1,
        'n' => if (operand.len > 0) 0 else 1,
        'e', 'f', 'd', 'r', 'w', 'x' => testFileOp(operand, op[1]),
        else => 1,
    };
}

fn makePath(path: []const u8, buf: *[4096:0]u8) ?[:0]u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

fn testFileOp(path: []const u8, kind: u8) u8 {
    var path_buf: [4096:0]u8 = undefined;
    const p = makePath(path, &path_buf) orelse return 1;
    switch (kind) {
        'e' => {
            var st: core.c.struct_stat = undefined;
            return if (core.c.stat(p.ptr, &st) == 0) 0 else 1;
        },
        'f' => {
            var st: core.c.struct_stat = undefined;
            if (core.c.stat(p.ptr, &st) != 0) return 1;
            return if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFREG) 0 else 1;
        },
        'd' => {
            var st: core.c.struct_stat = undefined;
            if (core.c.stat(p.ptr, &st) != 0) return 1;
            return if ((st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR) 0 else 1;
        },
        'r' => return if (core.c.access(p.ptr, core.c.R_OK) == 0) 0 else 1,
        'w' => return if (core.c.access(p.ptr, core.c.W_OK) == 0) 0 else 1,
        'x' => return if (core.c.access(p.ptr, core.c.X_OK) == 0) 0 else 1,
        else => return 1,
    }
}

fn testBinary(a: []const u8, op: []const u8, b: []const u8) u8 {
    if (std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "=="))
        return if (std.mem.eql(u8, a, b)) 0 else 1;
    if (std.mem.eql(u8, op, "!=")) return if (!std.mem.eql(u8, a, b)) 0 else 1;
    if (std.mem.eql(u8, op, "-eq")) return if (parseInt(a) == parseInt(b)) 0 else 1;
    if (std.mem.eql(u8, op, "-ne")) return if (parseInt(a) != parseInt(b)) 0 else 1;
    if (std.mem.eql(u8, op, "-lt")) return if (parseInt(a) < parseInt(b)) 0 else 1;
    if (std.mem.eql(u8, op, "-le")) return if (parseInt(a) <= parseInt(b)) 0 else 1;
    if (std.mem.eql(u8, op, "-gt")) return if (parseInt(a) > parseInt(b)) 0 else 1;
    if (std.mem.eql(u8, op, "-ge")) return if (parseInt(a) >= parseInt(b)) 0 else 1;
    return 1;
}

fn parseInt(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch std.math.maxInt(i64);
}
