const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "test", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len == 1) return 1;
    if (args.len == 2) return testUnary(args[1]);
    if (args.len == 3) {
        if (std.mem.eql(u8, args[1], "!"))
            return if (testUnary(args[2]) == 0) 1 else 0;
        return testUnaryOp(args[1], args[2]);
    }
    if (args.len == 4) {
        if (std.mem.eql(u8, args[1], "!"))
            return if (testUnaryOp(args[2], args[3]) == 0) 1 else 0;
        return testBinary(args[1], args[2], args[3]);
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "!"))
        return if (testBinary(args[2], args[3], args[4]) == 0) 1 else 0;
    return 1;
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
    if (std.mem.eql(u8, op, "==")) return if (std.mem.eql(u8, a, b)) 0 else 1;
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
