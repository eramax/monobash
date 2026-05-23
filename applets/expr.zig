const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "expr", .main = main };

const Parser = struct {
    tokens: [][]const u8,
    pos: usize,
    alloc: std.mem.Allocator,

    fn peek(self: *Parser) ?[]const u8 {
        if (self.pos >= self.tokens.len) return null;
        return self.tokens[self.pos];
    }

    fn next(self: *Parser) ?[]const u8 {
        const tok = self.peek();
        if (tok != null) self.pos += 1;
        return tok;
    }

    fn parseIntVal(s: []const u8) ?i64 {
        return std.fmt.parseInt(i64, s, 10) catch null;
    }

    fn atom(self: *Parser) !i64 {
        const tok = self.next() orelse return error.MissingOperand;
        if (parseIntVal(tok)) |v| return v;
        return error.NotInteger;
    }

    fn handleOp(self: *Parser, left: i64) !i64 {
        const op = self.next() orelse return left;
        const right = try self.atom();
        if (std.mem.eql(u8, op, "+")) return left + right;
        if (std.mem.eql(u8, op, "-")) return left - right;
        if (std.mem.eql(u8, op, "*")) return left * right;
        if (std.mem.eql(u8, op, "/")) {
            if (right == 0) return error.DivisionByZero;
            return @divTrunc(left, right);
        }
        if (std.mem.eql(u8, op, "%")) {
            if (right == 0) return error.DivisionByZero;
            return @mod(left, right);
        }
        if (std.mem.eql(u8, op, "|")) return @as(i64, @intCast(@as(u64, @bitCast(left)) | @as(u64, @bitCast(right))));
        if (std.mem.eql(u8, op, "&")) return @as(i64, @intCast(@as(u64, @bitCast(left)) & @as(u64, @bitCast(right))));
        if (std.mem.eql(u8, op, "<")) return if (left < right) 1 else 0;
        if (std.mem.eql(u8, op, "<=")) return if (left <= right) 1 else 0;
        if (std.mem.eql(u8, op, "==")) return if (left == right) 1 else 0;
        if (std.mem.eql(u8, op, "!=")) return if (left != right) 1 else 0;
        if (std.mem.eql(u8, op, ">=")) return if (left >= right) 1 else 0;
        if (std.mem.eql(u8, op, ">")) return if (left > right) 1 else 0;
        return error.UnknownOperator;
    }
};

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: expr EXPRESSION\n", .{});
    const tokens = args[1..];
    if (tokens.len >= 2) {
        if (std.mem.eql(u8, tokens[0], "length")) {
            core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "{d}\n", .{tokens[1].len}) catch return 1);
            return 0;
        }
        if (std.mem.eql(u8, tokens[0], "index")) {
            if (tokens.len < 3) return 1;
            const idx = std.mem.indexOfAny(u8, tokens[1], tokens[2]);
            if (idx) |i| {
                core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "{d}\n", .{i + 1}) catch return 1);
            } else {
                core.writeAll(1, "0\n");
            }
            return 0;
        }
        if (std.mem.eql(u8, tokens[0], "substr")) {
            if (tokens.len < 4) return 1;
            const pos = std.fmt.parseInt(usize, tokens[2], 10) catch return 1;
            const len = std.fmt.parseInt(usize, tokens[3], 10) catch return 1;
            if (pos < 1 or pos > tokens[1].len) {
                return 0;
            }
            const start = pos - 1;
            const end = @min(start + len, tokens[1].len);
            core.writeAll(1, tokens[1][start..end]);
            core.writeAll(1, "\n");
            return 0;
        }
        if (std.mem.eql(u8, tokens[0], "match")) {
            if (tokens.len < 3) return 1;
            const str = tokens[1];
            const pat = tokens[2];
            const matched = std.mem.startsWith(u8, str, pat);
            if (matched) {
                core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "{d}\n", .{pat.len}) catch return 1);
            } else {
                var rc: usize = 0;
                if (str.len > 0 and pat.len > 0 and pat[0] == '.') {
                    rc = 1;
                }
                core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "{d}\n", .{rc}) catch return 1);
            }
            return 0;
        }
    }
    var parser = Parser{
        .tokens = tokens,
        .pos = 0,
        .alloc = std.heap.page_allocator,
    };
    const left = parser.atom() catch return core.die(1, "expr: syntax error\n", .{});
    const result = parser.handleOp(left) catch return core.die(1, "expr: evaluation error\n", .{});
    core.writeAll(1, std.fmt.allocPrint(std.heap.page_allocator, "{d}\n", .{result}) catch return 1);
    return 0;
}
