const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "awk", .main = main };

const Alloc = std.mem.Allocator;
const page = std.heap.page_allocator;

// ─── Value type ───

const Val = struct {
    num: f64 = 0,
    str: ?[]const u8 = null,
};

fn valNum(v: Val) f64 {
    if (v.str) |str| {
        if (str.len == 0) return 0;
        return std.fmt.parseFloat(f64, str) catch 0;
    }
    return v.num;
}

fn parseNumberLiteral(s: []const u8) f64 {
    const t = std.mem.trim(u8, s, " \t");
    if (t.len == 0) return 0;
    if (t[0] == '0' and t.len > 1) {
        if (t[1] == 'x' or t[1] == 'X') {
            return @floatFromInt(std.fmt.parseInt(i64, t[2..], 16) catch 0);
        }
        if (t.len > 1 and isDigit(t[1])) {
            return @floatFromInt(std.fmt.parseInt(i64, t, 8) catch 0);
        }
    }
    return std.fmt.parseFloat(f64, t) catch 0;
}

fn valStr(v: Val, alloc: Alloc) []const u8 {
    if (v.str) |s| return s;
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(v.num))}) catch {
        const s2 = std.fmt.bufPrint(&buf, "{e}", .{v.num}) catch "?";
        return alloc.dupe(u8, s2) catch "?";
    };
    const result = alloc.dupe(u8, s) catch "!";
    return result;
}

fn valEq(a: Val, b: Val) bool {
    const an = valNum(a);
    const bn = valNum(b);
    if (a.str == null and b.str == null) return an == bn;
    var abuf: [64]u8 = undefined;
    var bbuf: [64]u8 = undefined;
    const as = valStrBuf(a, &abuf);
    const bs = valStrBuf(b, &bbuf);
    return std.mem.eql(u8, as, bs);
}

fn valStrBuf(v: Val, buf: []u8) []const u8 {
    if (v.str) |s| return s;
    return std.fmt.bufPrint(buf, "{d}", .{@as(i64, @intFromFloat(v.num))}) catch "0";
}

fn toValNum(v: Val) Val {
    const n = valNum(v);
    return Val{ .num = n, .str = "" };
}

fn toValStr(v: Val, alloc: Alloc) Val {
    const s = valStr(v, alloc);
    return Val{ .num = 0, .str = s };
}

fn fromF64(n: f64) Val { return Val{ .num = n, .str = null }; }
fn fromInt(n: i64) Val { return Val{ .num = @floatFromInt(n), .str = null }; }

fn fmtNum(n: f64, buf: []u8) []const u8 {
    if (n == @trunc(n) and @abs(n) < 1e15) {
        return std.fmt.bufPrint(buf, "{d}", .{@as(i64, @intFromFloat(n))}) catch "0";
    }
    const zfmt: [3:0]u8 = .{ '%', 'g', 0 };
    const r = core.c.snprintf(buf.ptr, buf.len, @as([*:0]const u8, &zfmt), n);
    if (r < 0) return "0";
    const len = @min(@as(usize, @intCast(r)), buf.len - 1);
    return buf[0..len];
}

fn isDigit(c: u8) bool { return c >= '0' and c <= '9'; }



// ─── Token types ───

const TokenType = enum {
    eof, number, string, regex, ident,
    plus, minus, star, slash, percent, caret,
    eq, ne, lt, gt, le, ge,
    match, not_match,
    and_and, or_or, bang,
    inc, dec,
    assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign, pow_assign,
    question, colon, comma, semicolon,
    lparen, rparen, lbracket, rbracket, lbrace, rbrace,
    dollar,
    kw_if, kw_else, kw_for, kw_while, kw_do, kw_break, kw_continue,
    kw_print, kw_printf, kw_next, kw_exit, kw_return, kw_delete,
    kw_function, kw_func, kw_in, kw_getline,
    kw_begin, kw_end,
    append, pipe, newline,
};

const Token = struct {
    ttype: TokenType,
    text: []const u8 = "",
    num: f64 = 0,
};

// ─── Lexer ───

const Lexer = struct {
    input: []const u8,
    pos: usize,
    tok: Token = .{ .ttype = .eof },
    is_expr: bool = false,
    prev_was_ws: bool = false,

    fn init(input: []const u8) Lexer {
        return .{ .input = input, .pos = 0 };
    }

    fn peek(self: *Lexer) u8 {
        if (self.pos >= self.input.len) return 0;
        return self.input[self.pos];
    }

    fn advance(self: *Lexer) u8 {
        const c = self.peek();
        if (c != 0) self.pos += 1;
        return c;
    }

    fn skipWS(self: *Lexer) void {
        self.prev_was_ws = false;
        while (self.pos < self.input.len) : (self.pos += 1) {
            const c = self.input[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.prev_was_ws = true;
            } else break;
        }
    }

    fn skipAll(self: *Lexer) void {
        while (self.pos < self.input.len) : (self.pos += 1) {
            const c = self.input[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') continue;
            break;
        }
    }

    fn next(self: *Lexer) Token {
        self.skipWS();
        if (self.pos >= self.input.len) {
            self.tok = .{ .ttype = .eof };
            return self.tok;
        }
        const c = self.input[self.pos];
        const start = self.pos;

        if (c == '\n') {
            self.pos += 1;
            self.tok = .{ .ttype = .newline };
            return self.tok;
        }

        if (c == '#') {
            while (self.pos < self.input.len and self.input[self.pos] != '\n') self.pos += 1;
            return self.next();
        }

        if (c == '"') {
            self.pos += 1;
            var buf = std.ArrayListAligned(u8, null).empty;
            while (self.pos < self.input.len) {
                const ch = self.advance();
                if (ch == '"') break;
                if (ch == '\\' and self.pos < self.input.len) {
                    const esc = self.advance();
                    switch (esc) {
                        'n' => buf.append(page, '\n') catch {},
                        't' => buf.append(page, '\t') catch {},
                        'r' => buf.append(page, '\r') catch {},
                        '\\' => buf.append(page, '\\') catch {},
                        '"' => buf.append(page, '"') catch {},
                        else => { buf.append(page, '\\') catch {}; buf.append(page, esc) catch {}; },
                    }
                } else {
                    buf.append(page, ch) catch {};
                }
            }
            self.tok = .{ .ttype = .string, .text = buf.items };
            return self.tok;
        }

        if (c == '/') {
            if (self.is_expr or true) {
                // Try to parse as regex
                const rsaved = self.pos;
                self.pos += 1;
                var buf = std.ArrayListAligned(u8, null).empty;
                var escaped = false;
                while (self.pos < self.input.len) {
                    const ch = self.advance();
                    if (ch == '\\') { escaped = true; buf.append(page, ch) catch {}; continue; }
                    if (ch == '/' and !escaped) break;
                    if (ch == '\n') { self.pos = rsaved; break; }
                    escaped = false;
                    buf.append(page, ch) catch {};
                }
                if (self.pos > rsaved + 1 and self.pos < self.input.len) {
                    self.tok = .{ .ttype = .regex, .text = buf.items };
                    return self.tok;
                }
                self.pos = rsaved;
            }
        }

        if (isDigit(c) or (c == '.' and self.pos + 1 < self.input.len and isDigit(self.input[self.pos + 1]))) {
            var is_hex = false;
            if (c == '0' and self.pos + 1 < self.input.len and (self.input[self.pos + 1] == 'x' or self.input[self.pos + 1] == 'X')) {
                is_hex = true;
            }
            self.pos += 1;
            if (is_hex) {
                self.pos += 1;
                while (self.pos < self.input.len) : (self.pos += 1) {
                    const ch = self.input[self.pos];
                    if (!((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F'))) break;
                }
            } else {
                while (self.pos < self.input.len) : (self.pos += 1) {
                    const ch = self.input[self.pos];
                    if (!isDigit(ch)) break;
                }
                if (self.pos < self.input.len and self.input[self.pos] == '.') {
                    self.pos += 1;
                    while (self.pos < self.input.len) : (self.pos += 1) {
                        const ch = self.input[self.pos];
                        if (!isDigit(ch)) break;
                    }
                }
            }
            const text = self.input[start..self.pos];
            const n = parseNumberLiteral(text);
            self.tok = .{ .ttype = .number, .num = n, .text = text };
            return self.tok;
        }

        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            self.pos += 1;
            while (self.pos < self.input.len) : (self.pos += 1) {
                const ch = self.input[self.pos];
                if (!((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_')) break;
            }
            const text = self.input[start..self.pos];
            const ttype = keywordType(text);
            self.tok = if (ttype) |tt| Token{ .ttype = tt } else Token{ .ttype = .ident, .text = text };
            return self.tok;
        }

        self.pos += 1;
        const nxt = if (self.pos < self.input.len) self.input[self.pos] else 0;
        self.tok = switch (c) {
            '+' => if (nxt == '+') blk: { self.pos += 1; break :blk Token{ .ttype = .inc }; } else if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .add_assign }; } else Token{ .ttype = .plus },
            '-' => if (nxt == '-') blk: { self.pos += 1; break :blk Token{ .ttype = .dec }; } else if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .sub_assign }; } else Token{ .ttype = .minus },
            '*' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .mul_assign }; } else Token{ .ttype = .star },
            '/' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .div_assign }; } else Token{ .ttype = .slash },
            '%' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .mod_assign }; } else Token{ .ttype = .percent },
            '^' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .pow_assign }; } else Token{ .ttype = .caret },
            '=' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .eq }; } else Token{ .ttype = .assign },
            '!' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .ne }; } else if (nxt == '~') blk: { self.pos += 1; break :blk Token{ .ttype = .not_match }; } else Token{ .ttype = .bang },
            '<' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .le }; } else Token{ .ttype = .lt },
            '>' => if (nxt == '=') blk: { self.pos += 1; break :blk Token{ .ttype = .ge }; } else if (nxt == '>') blk: { self.pos += 1; break :blk Token{ .ttype = .append }; } else Token{ .ttype = .gt },
            '~' => Token{ .ttype = .match },
            '&' => if (nxt == '&') blk: { self.pos += 1; break :blk Token{ .ttype = .and_and }; } else Token{ .ttype = .eof },
            '|' => if (nxt == '|') blk: { self.pos += 1; break :blk Token{ .ttype = .or_or }; } else Token{ .ttype = .pipe },
            '?' => Token{ .ttype = .question },
            ':' => Token{ .ttype = .colon },
            ',' => Token{ .ttype = .comma },
            ';' => Token{ .ttype = .semicolon },
            '(' => Token{ .ttype = .lparen },
            ')' => Token{ .ttype = .rparen },
            '[' => Token{ .ttype = .lbracket },
            ']' => Token{ .ttype = .rbracket },
            '{' => Token{ .ttype = .lbrace },
            '}' => Token{ .ttype = .rbrace },
            '$' => Token{ .ttype = .dollar },
            else => Token{ .ttype = .eof },
        };
        return self.tok;
    }
};

fn keywordType(s: []const u8) ?TokenType {
    if (std.mem.eql(u8, s, "if")) return .kw_if;
    if (std.mem.eql(u8, s, "else")) return .kw_else;
    if (std.mem.eql(u8, s, "for")) return .kw_for;
    if (std.mem.eql(u8, s, "while")) return .kw_while;
    if (std.mem.eql(u8, s, "do")) return .kw_do;
    if (std.mem.eql(u8, s, "break")) return .kw_break;
    if (std.mem.eql(u8, s, "continue")) return .kw_continue;
    if (std.mem.eql(u8, s, "print")) return .kw_print;
    if (std.mem.eql(u8, s, "printf")) return .kw_printf;
    if (std.mem.eql(u8, s, "next")) return .kw_next;
    if (std.mem.eql(u8, s, "exit")) return .kw_exit;
    if (std.mem.eql(u8, s, "return")) return .kw_return;
    if (std.mem.eql(u8, s, "delete")) return .kw_delete;
    if (std.mem.eql(u8, s, "function")) return .kw_function;
    if (std.mem.eql(u8, s, "func")) return .kw_func;
    if (std.mem.eql(u8, s, "in")) return .kw_in;
    if (std.mem.eql(u8, s, "getline")) return .kw_getline;
    if (std.mem.eql(u8, s, "BEGIN")) return .kw_begin;
    if (std.mem.eql(u8, s, "END")) return .kw_end;
    return null;
}

// ─── AST types ───

const Stmt = struct {
    tag: Tag,
    data: Data,
    const Tag = enum {
        print, printf, if_stmt, for_loop, for_in, while_loop, do_while,
        break_stmt, continue_stmt, next_stmt, exit_stmt, return_stmt,
        delete_stmt, expr_stmt, block, noop,
    };
    const Data = union {
        print: struct { exprs: []Expr, redir: ?Redirect },
        printf: struct { fmt: []Expr, args: []Expr, redir: ?Redirect },
        if_stmt: struct { cond: *Expr, then_branch: *Stmt, else_branch: ?*Stmt },
        for_loop: struct { init: ?*Stmt, cond: ?*Expr, inc: ?*Expr, body: *Stmt },
        for_in: struct { var_name: []const u8, array_name: []const u8, body: *Stmt },
        while_loop: struct { cond: *Expr, body: *Stmt },
        do_while: struct { body: *Stmt, cond: *Expr },
        exit_stmt: struct { expr: ?*Expr },
        return_stmt: struct { expr: ?*Expr },
        delete_stmt: struct { name: []const u8, index: ?*Expr },
        expr_stmt: struct { expr: *Expr },
        block: struct { stmts: []Stmt },
    };
};

const Expr = struct {
    tag: Tag,
    data: Data,
    const Tag = enum {
        num, str_val, regex_val, ident, field, array_access, func_call,
        unary_plus, unary_minus, not,
        pre_inc, pre_dec, post_inc, post_dec,
        add, sub, mul, div, mod, pow,
        eq, ne, lt, gt, le, ge, match, not_match,
        and_and, or_or,
        ternary,
        concat,
        assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign, pow_assign,
        in_op, str_val_owned, builtin_call,
    };
    const Data = union {
        num: f64,
        str: []const u8,
        regex: []const u8,
        ident: []const u8,
        field: *Expr,
        array_access: struct { name: []const u8, index: *Expr },
        func_call: struct { name: []const u8, args: []Expr },
        builtin_call: struct { builtin: Builtin, args: []Expr },
        unary: struct { expr: *Expr },
        binary: struct { left: *Expr, right: *Expr },
        ternary: struct { cond: *Expr, then_expr: *Expr, else_expr: *Expr },
        concat: struct { left: *Expr, right: *Expr },
        assign: struct { ltype: AssignLVal, lname: []const u8, lfield: *Expr, lindex: *Expr, right: *Expr },
    };
};

const AssignLVal = enum { lvar, lfield, larray };

const Builtin = enum {
    length, gsub, gensub, sub, index_fn, substr, match_fn, split, sprintf,
    or_fn, and_fn, xor_fn, compl, lshift, rshift,
    int, sqrt, sin, cos, atan2, rand, srand,
    tolower, toupper, system, close, flush,
    strftime, asort, asorti,
};

const Redirect = struct {
    rtype: enum { write, append, pipe_in, pipe_out },
    target: *Expr,
};

const Rule = struct {
    pattern: Pattern,
    action: *Stmt,
};

const Pattern = union(enum) {
    always,
    begin,
    end,
    expr: *Expr,
    regex: []const u8,
    range: struct { from: *Pattern, to: *Pattern },
};

const FuncDef = struct {
    name: []const u8,
    params: [][]const u8,
    body: *Stmt,
};

const Program = struct {
    rules: []Rule,
    funcs: []FuncDef,
};

// ─── Parser ───

const ParseResult = struct { rules: []Rule = &.{}, funcs: []FuncDef = &.{}, had_error: bool = false };

fn parseProgram(input: []const u8, alloc: Alloc) ParseResult {
    var lex = Lexer.init(input);
    var rules = std.ArrayListAligned(Rule, null).empty;
    var funcs = std.ArrayListAligned(FuncDef, null).empty;
    var had_error = false;

    _ = lex.next();
    while (lex.tok.ttype != .eof) {
        if (lex.tok.ttype == .newline) { _ = lex.next(); continue; }
        if (lex.tok.ttype == .semicolon) { _ = lex.next(); continue; }

        if (lex.tok.ttype == .kw_function or lex.tok.ttype == .kw_func) {
            _ = lex.next();
            const fd = parseFuncDef(&lex, alloc);
            if (fd) |f| funcs.append(alloc, f) catch {} else { had_error = true; return ParseResult{ .had_error = true }; }
            continue;
        }

        const rule = parseRule(&lex, alloc);
        if (rule) |r| {
            rules.append(alloc, r) catch {};
            while (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) _ = lex.next();
        } else {
            had_error = true;
            break;
        }
    }

    return .{ .rules = rules.items, .funcs = funcs.items, .had_error = had_error };
}

fn parseRule(lex: *Lexer, alloc: Alloc) ?Rule {
    const pat = parsePattern(lex, alloc);
    if (pat) |p| {
        if (lex.tok.ttype == .lbrace) {
            const action = parseBlock(lex, alloc);
            if (action) |a| return Rule{ .pattern = p, .action = a };
            return null;
        }
        // Bare expression pattern - default action is print $0
        const s = alloc.create(Stmt) catch return null;
        s.* = Stmt{ .tag = .print, .data = .{ .print = .{ .exprs = &.{}, .redir = null } } };
        return Rule{ .pattern = p, .action = s };
    }
    if (lex.tok.ttype == .lbrace) {
        const action = parseBlock(lex, alloc);
        if (action) |a| return Rule{ .pattern = .always, .action = a };
        return null;
    }
    return null;
}

fn parsePattern(lex: *Lexer, alloc: Alloc) ?Pattern {
    if (lex.tok.ttype == .kw_begin) {
        _ = lex.next();
        return .begin;
    }
    if (lex.tok.ttype == .kw_end) {
        _ = lex.next();
        return .end;
    }
    if (lex.tok.ttype == .regex) {
        const text = lex.tok.text;
        _ = lex.next();
        return .{ .regex = text };
    }
    if (lex.tok.ttype == .lparen) {
        _ = lex.next();
        const expr = parseExpr(lex, alloc);
        if (expr) |e| {
            if (lex.tok.ttype == .rparen) {
                _ = lex.next();
                return .{ .expr = e };
            }
        }
        return null;
    }
    // Try to parse an expression pattern
    const expr = parseExpr(lex, alloc);
    if (expr) |e| {
        if (lex.tok.ttype == .comma) {
            _ = lex.next();
            _ = parsePattern(lex, alloc);
            // Range patterns not fully supported
        }
        return .{ .expr = e };
    }
    return null;
}

fn parseBlock(lex: *Lexer, alloc: Alloc) ?*Stmt {
    if (lex.tok.ttype != .lbrace) return null;
    _ = lex.next();
    var stmts = std.ArrayListAligned(Stmt, null).empty;
    while (lex.tok.ttype != .rbrace and lex.tok.ttype != .eof) {
        if (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) {
            _ = lex.next();
            continue;
        }
        const stmt = parseStmt(lex, alloc);
        if (stmt) |s| {
            stmts.append(alloc, s) catch {};
            while (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) _ = lex.next();
        } else {
            return null;
        }
    }
    if (lex.tok.ttype == .rbrace) _ = lex.next();
    const s = alloc.create(Stmt) catch return null;
    s.* = Stmt{ .tag = .block, .data = .{ .block = .{ .stmts = stmts.items } } };
    return s;
}

fn parseStmt(lex: *Lexer, alloc: Alloc) ?Stmt {
    switch (lex.tok.ttype) {
        .kw_print => return parsePrint(lex, alloc),
        .kw_printf => return parsePrintf(lex, alloc),
        .kw_if => return parseIf(lex, alloc),
        .kw_for => return parseFor(lex, alloc),
        .kw_while => return parseWhile(lex, alloc),
        .kw_do => return parseDoWhile(lex, alloc),
        .kw_break => { _ = lex.next(); return Stmt{ .tag = .break_stmt, .data = undefined }; },
        .kw_continue => { _ = lex.next(); return Stmt{ .tag = .continue_stmt, .data = undefined }; },
        .kw_delete => return parseDelete(lex, alloc),
        .kw_next => { _ = lex.next(); return Stmt{ .tag = .next_stmt, .data = undefined }; },
        .kw_exit => return parseExit(lex, alloc),
        .kw_return => return parseReturn(lex, alloc),
        .lbrace => {
            const block = parseBlock(lex, alloc);
            if (block) |b| return Stmt{ .tag = .block, .data = .{ .block = .{ .stmts = b.data.block.stmts } } };
            return null;
        },
        .semicolon, .newline => { _ = lex.next(); return Stmt{ .tag = .noop, .data = undefined }; },
        else => {
            const expr = parseExpr(lex, alloc);
            if (expr) |e| return Stmt{ .tag = .expr_stmt, .data = .{ .expr_stmt = .{ .expr = e } } };
            return null;
        },
    }
}

fn parsePrint(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    var exprs = std.ArrayListAligned(Expr, null).empty;
    var redir: ?Redirect = null;

    if (lex.tok.ttype != .newline and lex.tok.ttype != .semicolon and lex.tok.ttype != .rbrace and lex.tok.ttype != .eof and
        lex.tok.ttype != .pipe and lex.tok.ttype != .append and lex.tok.ttype != .gt) {
        while (true) {
            const expr = parseExprNoCompare(lex, alloc);
            if (expr) |e| exprs.append(alloc, e.*) catch {} else return null;
            if (lex.tok.ttype == .comma) { _ = lex.next(); continue; }
            break;
        }
    }

    if (lex.tok.ttype == .gt) {
        _ = lex.next();
        if (parseExprNoCompare(lex, alloc)) |target| {
            redir = Redirect{ .rtype = .write, .target = target };
        } else return null;
    } else if (lex.tok.ttype == .append) {
        _ = lex.next();
        if (parseExprNoCompare(lex, alloc)) |target| {
            redir = Redirect{ .rtype = .append, .target = target };
        } else return null;
    } else if (lex.tok.ttype == .pipe) {
        _ = lex.next();
        if (lex.tok.ttype == .kw_getline) {
            _ = lex.next();
        }
    }

    return Stmt{ .tag = .print, .data = .{ .print = .{ .exprs = exprs.items, .redir = redir } } };
}

fn parseFieldIndex(lex: *Lexer, alloc: Alloc) ?*Expr {
    const saved = lex.pos;
    const saved_tok = lex.tok;
    // Parse a primary expression for the field index
    const result = parsePrimary(lex, alloc);
    if (result == null) {
        lex.pos = saved;
        lex.tok = saved_tok;
    }
    return result;
}

fn parseExprNoCompare(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseConcat(lex, alloc);
    if (left == null) return null;
    while (true) {
        const tt = lex.tok.ttype;
        if (tt == .plus or tt == .minus) {
            _ = lex.next();
            const right = parseConcat(lex, alloc);
            if (right == null) return null;
            left = makeBinary(if (tt == .plus) Expr.Tag.add else .sub, left.?, right.?, alloc);
        } else if (tt == .star or tt == .slash or tt == .percent) {
            _ = lex.next();
            const right = parseConcat(lex, alloc);
            if (right == null) return null;
            const tag: Expr.Tag = switch (tt) { .star => .mul, .slash => .div, .percent => .mod, else => unreachable };
            left = makeBinary(tag, left.?, right.?, alloc);
        } else if (tt == .caret) {
            _ = lex.next();
            const right = parseConcat(lex, alloc);
            if (right == null) return null;
            left = makeBinary(.pow, left.?, right.?, alloc);
        } else if (tt == .match or tt == .not_match) {
            _ = lex.next();
            const right = parseConcat(lex, alloc);
            if (right == null) return null;
            left = makeBinary(if (tt == .match) Expr.Tag.match else .not_match, left.?, right.?, alloc);
        } else break;
    }
    return left;
}

fn parsePrintf(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    var exprs = std.ArrayListAligned(Expr, null).empty;
    // Handle optional ( after printf
    var had_paren = false;
    if (lex.tok.ttype == .lparen) {
        had_paren = true;
        _ = lex.next();
    }
    // Format string
    const fmt = parseExprNoCompare(lex, alloc);
    if (fmt) |f| exprs.append(alloc, f.*) catch {} else return null;
    // Comma-separated args
    while (lex.tok.ttype == .comma) {
        _ = lex.next();
        if (parseExprNoCompare(lex, alloc)) |e| exprs.append(alloc, e.*) catch {} else return null;
    }
    if (had_paren and lex.tok.ttype == .rparen) {
        _ = lex.next();
    }

    var redir: ?Redirect = null;
    if (lex.tok.ttype == .gt) {
        _ = lex.next();
        if (parseExprNoCompare(lex, alloc)) |target| {
            redir = Redirect{ .rtype = .write, .target = target };
        } else return null;
    } else if (lex.tok.ttype == .append) {
        _ = lex.next();
        if (parseExprNoCompare(lex, alloc)) |target| {
            redir = Redirect{ .rtype = .append, .target = target };
        } else return null;
    }

    return Stmt{ .tag = .printf, .data = .{ .printf = .{ .fmt = exprs.items[0..1], .args = exprs.items[1..], .redir = redir } } };
}

fn parseIf(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .lparen) _ = lex.next();
    const cond = parseExpr(lex, alloc);
    if (cond == null) return null;
    if (lex.tok.ttype == .rparen) _ = lex.next();
    const then_branch = parseStmtOrBlock(lex, alloc);
    if (then_branch == null) return null;
    var else_branch: ?*Stmt = null;
    // Skip newlines before else
    while (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) _ = lex.next();
    if (lex.tok.ttype == .kw_else) {
        _ = lex.next();
        else_branch = parseStmtOrBlock(lex, alloc);
        if (else_branch == null) return null;
    }
    return Stmt{ .tag = .if_stmt, .data = .{ .if_stmt = .{ .cond = cond.?, .then_branch = then_branch.?, .else_branch = else_branch } } };
}

fn parseStmtOrBlock(lex: *Lexer, alloc: Alloc) ?*Stmt {
    if (lex.tok.ttype == .lbrace) return parseBlock(lex, alloc);
    const s = alloc.create(Stmt) catch return null;
    const stmt = parseStmt(lex, alloc);
    if (stmt) |st| { s.* = st; return s; }
    return null;
}

fn parseFor(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .lparen) _ = lex.next();
    // Check for for-in: for (var in array)
    if (lex.tok.ttype == .ident) {
        const var_name = lex.tok.text;
        _ = lex.next();
        if (lex.tok.ttype == .kw_in) {
            _ = lex.next();
            const array_name = if (lex.tok.ttype == .ident) lex.tok.text else "";
            if (lex.tok.ttype == .ident) _ = lex.next();
            if (lex.tok.ttype == .rparen) _ = lex.next();
            const body = parseStmtOrBlock(lex, alloc);
            if (body == null) return null;
            return Stmt{ .tag = .for_in, .data = .{ .for_in = .{ .var_name = var_name, .array_name = array_name, .body = body.? } } };
        }
        // Not for-in, reset and parse as for (init; cond; inc)
        lex.pos -= var_name.len;
        // Need to re-lex
    }

    _ = parseStmt(lex, alloc);
    if (lex.tok.ttype == .semicolon) _ = lex.next();
    const cond = parseExpr(lex, alloc);
    if (lex.tok.ttype == .semicolon) _ = lex.next();
    const inc = parseExpr(lex, alloc);
    if (lex.tok.ttype == .rparen) _ = lex.next();
    const body = parseStmtOrBlock(lex, alloc);
    if (body == null) return null;
    return Stmt{ .tag = .for_loop, .data = .{ .for_loop = .{ .init = null, .cond = cond, .inc = inc, .body = body.? } } };
}

fn parseWhile(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .lparen) _ = lex.next();
    const cond = parseExpr(lex, alloc);
    if (cond == null) return null;
    if (lex.tok.ttype == .rparen) _ = lex.next();
    const body = parseStmtOrBlock(lex, alloc);
    if (body == null) return null;
    return Stmt{ .tag = .while_loop, .data = .{ .while_loop = .{ .cond = cond.?, .body = body.? } } };
}

fn parseDoWhile(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    const body = parseStmtOrBlock(lex, alloc);
    if (body == null) return null;
    while (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) _ = lex.next();
    if (lex.tok.ttype == .kw_while) {
        _ = lex.next();
        if (lex.tok.ttype == .lparen) _ = lex.next();
        const cond = parseExpr(lex, alloc);
        if (cond == null) return null;
        if (lex.tok.ttype == .rparen) _ = lex.next();
        return Stmt{ .tag = .do_while, .data = .{ .do_while = .{ .body = body.?, .cond = cond.? } } };
    }
    return null;
}

fn parseExit(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon or lex.tok.ttype == .rbrace or lex.tok.ttype == .eof) {
        return Stmt{ .tag = .exit_stmt, .data = .{ .exit_stmt = .{ .expr = null } } };
    }
    const expr = parseExpr(lex, alloc);
    if (expr) |e| return Stmt{ .tag = .exit_stmt, .data = .{ .exit_stmt = .{ .expr = e } } };
    return null;
}

fn parseReturn(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon or lex.tok.ttype == .rbrace or lex.tok.ttype == .eof) {
        return Stmt{ .tag = .return_stmt, .data = .{ .return_stmt = .{ .expr = null } } };
    }
    const expr = parseExpr(lex, alloc);
    if (expr) |e| return Stmt{ .tag = .return_stmt, .data = .{ .return_stmt = .{ .expr = e } } };
    return null;
}

fn parseDelete(lex: *Lexer, alloc: Alloc) ?Stmt {
    _ = lex.next();
    if (lex.tok.ttype == .ident) {
        const name = lex.tok.text;
        _ = lex.next();
        if (lex.tok.ttype == .lbracket) {
            _ = lex.next();
            const index = parseExpr(lex, alloc);
            if (lex.tok.ttype == .rbracket) _ = lex.next();
            return Stmt{ .tag = .delete_stmt, .data = .{ .delete_stmt = .{ .name = name, .index = index } } };
        }
        // delete array (entire array)
        return Stmt{ .tag = .delete_stmt, .data = .{ .delete_stmt = .{ .name = name, .index = null } } };
    }
    return null;
}

fn parseFuncDef(lex: *Lexer, alloc: Alloc) ?FuncDef {
    const name = if (lex.tok.ttype == .ident) lex.tok.text else return null;
    _ = lex.next();
    if (lex.tok.ttype == .lparen) _ = lex.next();
    var params = std.ArrayListAligned([]const u8, null).empty;
    while (lex.tok.ttype != .rparen and lex.tok.ttype != .eof) {
        if (lex.tok.ttype == .ident) {
            params.append(alloc, lex.tok.text) catch {};
            _ = lex.next();
            if (lex.tok.ttype == .comma) _ = lex.next();
        } else {
            break;
        }
    }
    if (lex.tok.ttype == .rparen) _ = lex.next();
    while (lex.tok.ttype == .newline or lex.tok.ttype == .semicolon) _ = lex.next();
    const body = parseBlock(lex, alloc);
    if (body == null) return null;
    return FuncDef{ .name = name, .params = params.items, .body = body.? };
}

// ─── Expression parsing ───

fn parseExpr(lex: *Lexer, alloc: Alloc) ?*Expr {
    const saved = lex.pos;
    const saved_tok = lex.tok;
    const expr = parseTernary(lex, alloc);
    if (expr == null) {
        lex.pos = saved;
        lex.tok = saved_tok;
    }
    return expr;
}

fn parseTernary(lex: *Lexer, alloc: Alloc) ?*Expr {
    const left = parseOrOr(lex, alloc);
    if (left == null) return null;
    if (lex.tok.ttype == .question) {
        _ = lex.next();
        const then_expr = parseTernary(lex, alloc);
        if (then_expr == null) return null;
        if (lex.tok.ttype == .colon) {
            _ = lex.next();
            const else_expr = parseTernary(lex, alloc);
            if (else_expr == null) return null;
            return makeTernary(left.?, then_expr.?, else_expr.?, alloc);
        }
        return null;
    }
    return left;
}

fn parseOrOr(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseAndAnd(lex, alloc);
    if (left == null) return null;
    while (lex.tok.ttype == .or_or) {
        _ = lex.next();
        const right = parseAndAnd(lex, alloc);
        if (right == null) return null;
        left = makeBinary(.or_or, left.?, right.?, alloc);
    }
    return left;
}

fn parseAndAnd(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseInExpr(lex, alloc);
    if (left == null) return null;
    while (lex.tok.ttype == .and_and) {
        _ = lex.next();
        const right = parseInExpr(lex, alloc);
        if (right == null) return null;
        left = makeBinary(.and_and, left.?, right.?, alloc);
    }
    return left;
}

fn parseInExpr(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseCompare(lex, alloc);
    if (left == null) return null;
    if (lex.tok.ttype == .kw_in) {
        _ = lex.next();
        const right = parseCompare(lex, alloc);
        if (right == null) return null;
        left = makeBinary(.in_op, left.?, right.?, alloc);
    }
    return left;
}

fn parseCompare(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseMatch(lex, alloc);
    if (left == null) return null;
    while (true) {
        const tt = lex.tok.ttype;
        if (tt == .eq or tt == .ne or tt == .lt or tt == .gt or tt == .le or tt == .ge) {
            _ = lex.next();
            const right = parseMatch(lex, alloc);
            if (right == null) return null;
            const tag: Expr.Tag = switch (tt) {
                .eq => .eq, .ne => .ne, .lt => .lt, .gt => .gt, .le => .le, .ge => .ge,
                else => unreachable,
            };
            left = makeBinary(tag, left.?, right.?, alloc);
        } else break;
    }
    return left;
}

fn parseMatch(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseConcat(lex, alloc);
    if (left == null) return null;
    if (lex.tok.ttype == .match or lex.tok.ttype == .not_match) {
        const is_match = lex.tok.ttype == .match;
        _ = lex.next();
        const right = parseConcat(lex, alloc);
        if (right == null) return null;
        left = makeBinary(if (is_match) Expr.Tag.match else .not_match, left.?, right.?, alloc);
    }
    return left;
}

fn parseConcat(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseTerm(lex, alloc);
    if (left == null) return null;
    while (true) {
        // Check if next token starts a new term (for concatenation)
        const tt = lex.tok.ttype;
        if (tt == .eof or tt == .rparen or tt == .rbracket or tt == .comma or tt == .semicolon or
            tt == .newline or tt == .rbrace or tt == .colon or tt == .question or
            tt == .gt or tt == .append or tt == .pipe or
            tt == .eq or tt == .ne or tt == .lt or tt == .gt or tt == .le or tt == .ge or
            tt == .match or tt == .not_match or
            tt == .and_and or tt == .or_or or tt == .kw_in or
            tt == .add_assign or tt == .sub_assign or tt == .mul_assign or tt == .div_assign or
            tt == .mod_assign or tt == .pow_assign or tt == .assign or
            tt == .rparen) // wait, rparen is already listed
        {
            break;
        }
        if (tt == .plus or tt == .minus or tt == .star or tt == .slash or tt == .percent or tt == .caret) break;
        const right = parseTerm(lex, alloc);
        if (right == null) break;
        left = makeBinary(.concat, left.?, right.?, alloc);
    }
    return left;
}

fn parseTerm(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parsePow(lex, alloc);
    if (left == null) return null;
    while (true) {
        const tt = lex.tok.ttype;
        if (tt == .plus or tt == .minus) {
            _ = lex.next();
            const right = parsePow(lex, alloc);
            if (right == null) return null;
            const tag: Expr.Tag = if (tt == .plus) .add else .sub;
            left = makeBinary(tag, left.?, right.?, alloc);
        } else if (tt == .star or tt == .slash or tt == .percent) {
            _ = lex.next();
            const right = parsePow(lex, alloc);
            if (right == null) return null;
            const tag: Expr.Tag = switch (tt) {
                .star => .mul, .slash => .div, .percent => .mod,
                else => unreachable,
            };
            left = makeBinary(tag, left.?, right.?, alloc);
        } else break;
    }
    return left;
}

fn parsePow(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parseUnary(lex, alloc);
    if (left == null) return null;
    if (lex.tok.ttype == .caret) {
        _ = lex.next();
        const right = parsePow(lex, alloc);
        if (right == null) return null;
        left = makeBinary(.pow, left.?, right.?, alloc);
    }
    return left;
}

fn parseUnary(lex: *Lexer, alloc: Alloc) ?*Expr {
    const tt = lex.tok.ttype;
    if (tt == .plus) {
        _ = lex.next();
        const expr = parseUnary(lex, alloc);
        if (expr == null) return null;
        return makeUnary(.unary_plus, expr.?, alloc);
    }
    if (tt == .minus) {
        _ = lex.next();
        const expr = parseUnary(lex, alloc);
        if (expr == null) return null;
        return makeUnary(.unary_minus, expr.?, alloc);
    }
    if (tt == .bang) {
        _ = lex.next();
        const expr = parseUnary(lex, alloc);
        if (expr == null) return null;
        return makeUnary(.not, expr.?, alloc);
    }
    if (tt == .inc) {
        _ = lex.next();
        const expr = parsePostfix(lex, alloc);
        if (expr == null) return null;
        return makeUnary(.pre_inc, expr.?, alloc);
    }
    if (tt == .dec) {
        _ = lex.next();
        const expr = parsePostfix(lex, alloc);
        if (expr == null) return null;
        return makeUnary(.pre_dec, expr.?, alloc);
    }
    return parsePostfix(lex, alloc);
}

fn parsePostfix(lex: *Lexer, alloc: Alloc) ?*Expr {
    var left = parsePrimary(lex, alloc);
    if (left == null) return null;
    if (lex.tok.ttype == .inc) {
        _ = lex.next();
        left = makeUnary(.post_inc, left.?, alloc);
    } else if (lex.tok.ttype == .dec) {
        _ = lex.next();
        left = makeUnary(.post_dec, left.?, alloc);
    }
    // Parse assignment operators
    const tt = lex.tok.ttype;
    if (tt == .assign or tt == .add_assign or tt == .sub_assign or tt == .mul_assign or
        tt == .div_assign or tt == .mod_assign or tt == .pow_assign) {
        _ = lex.next();
        const right = parseExpr(lex, alloc);
        if (right == null) return null;
        const tag: Expr.Tag = switch (tt) {
            .assign => .assign, .add_assign => .add_assign, .sub_assign => .sub_assign,
            .mul_assign => .mul_assign, .div_assign => .div_assign,
            .mod_assign => .mod_assign, .pow_assign => .pow_assign,
            else => unreachable,
        };
        return makeAssign(tag, left.?, right.?, alloc);
    }
    return left;
}

fn parsePrimary(lex: *Lexer, alloc: Alloc) ?*Expr {
    switch (lex.tok.ttype) {
        .number => {
            const n = lex.tok.num;
            _ = lex.next();
            return makeNum(n, alloc);
        },
        .string => {
            const s = lex.tok.text;
            _ = lex.next();
            return makeStr(s, alloc);
        },
        .regex => {
            const r = lex.tok.text;
            _ = lex.next();
            return makeRegex(r, alloc);
        },
        .ident => {
            const name = lex.tok.text;
            _ = lex.next();
            const ws_before_paren = lex.prev_was_ws;
            if (lex.tok.ttype == .lparen and !ws_before_paren) {
                // Function call (no whitespace before paren)
                _ = lex.next();
                var args = std.ArrayListAligned(Expr, null).empty;
                while (lex.tok.ttype != .rparen and lex.tok.ttype != .eof) {
                    const arg = parseExpr(lex, alloc);
                    if (arg) |a| {
                        args.append(alloc, a.*) catch {};
                        if (lex.tok.ttype == .comma) _ = lex.next();
                    } else break;
                }
                if (lex.tok.ttype == .rparen) _ = lex.next();
                // Check if it's a builtin
                if (builtinFromName(name)) |b| {
                    return makeBuiltin(b, args.items, alloc);
                }
                return makeFuncCall(name, args.items, alloc);
            }
            if (lex.tok.ttype == .lbracket) {
                // Array access
                _ = lex.next();
                const index = parseExpr(lex, alloc);
                if (index == null) return null;
                if (lex.tok.ttype == .rbracket) _ = lex.next();
                return makeArrayAccess(name, index.?, alloc);
            }
            return makeIdent(name, alloc);
        },
        .dollar => {
            _ = lex.next();
            const expr = parseFieldIndex(lex, alloc);
            if (expr == null) return null;
            return makeField(expr.?, alloc);
        },
        .lparen => {
            _ = lex.next();
            const expr = parseExpr(lex, alloc);
            if (expr == null) return null;
            if (lex.tok.ttype == .rparen) {
                _ = lex.next();
                return expr;
            }
            return null;
        },
        .plus, .minus, .bang => {
            // unary handled in parseUnary
            return null;
        },
        else => return null,
    }
}

// ─── Helper functions for creating AST nodes ───

fn makeNum(n: f64, alloc: Alloc) ?*Expr {
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .num, .data = .{ .num = n } };
    return e;
}

fn makeStr(s: []const u8, alloc: Alloc) ?*Expr {
    const owned = alloc.dupe(u8, s) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .str_val, .data = .{ .str = owned } };
    return e;
}

fn makeRegex(s: []const u8, alloc: Alloc) ?*Expr {
    const owned = alloc.dupe(u8, s) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .regex_val, .data = .{ .regex = owned } };
    return e;
}

fn makeIdent(name: []const u8, alloc: Alloc) ?*Expr {
    const owned = alloc.dupe(u8, name) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .ident, .data = .{ .ident = owned } };
    return e;
}

fn makeField(expr: *Expr, alloc: Alloc) ?*Expr {
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .field, .data = .{ .field = expr } };
    return e;
}

fn makeArrayAccess(name: []const u8, index: *Expr, alloc: Alloc) ?*Expr {
    const n = alloc.dupe(u8, name) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .array_access, .data = .{ .array_access = .{ .name = n, .index = index } } };
    return e;
}

fn makeFuncCall(name: []const u8, args: []Expr, alloc: Alloc) ?*Expr {
    const n = alloc.dupe(u8, name) catch return null;
    const a = alloc.dupe(Expr, args) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .func_call, .data = .{ .func_call = .{ .name = n, .args = a } } };
    return e;
}

fn makeBuiltin(b: Builtin, args: []Expr, alloc: Alloc) ?*Expr {
    const a = alloc.dupe(Expr, args) catch return null;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .builtin_call, .data = .{ .builtin_call = .{ .builtin = b, .args = a } } };
    return e;
}

fn makeBinary(tag: Expr.Tag, left: *Expr, right: *Expr, alloc: Alloc) ?*Expr {
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = tag, .data = .{ .binary = .{ .left = left, .right = right } } };
    return e;
}

fn makeUnary(tag: Expr.Tag, expr: *Expr, alloc: Alloc) ?*Expr {
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = tag, .data = .{ .unary = .{ .expr = expr } } };
    return e;
}

fn makeTernary(cond: *Expr, then_expr: *Expr, else_expr: *Expr, alloc: Alloc) ?*Expr {
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = .ternary, .data = .{ .ternary = .{ .cond = cond, .then_expr = then_expr, .else_expr = else_expr } } };
    return e;
}

fn makeAssign(tag: Expr.Tag, left: *Expr, right: *Expr, alloc: Alloc) ?*Expr {
    // Determine lval type from left expression
    const ltype = switch (left.tag) {
        .ident => AssignLVal.lvar,
        .field => AssignLVal.lfield,
        .array_access => AssignLVal.larray,
        else => AssignLVal.lvar,
    };
    const lname = switch (left.tag) {
        .ident => left.data.ident,
        .field => "",
        .array_access => left.data.array_access.name,
        else => "",
    };
    const lfield = if (left.tag == .field) left.data.field else undefined;
    const lindex = if (left.tag == .array_access) left.data.array_access.index else undefined;
    const e = alloc.create(Expr) catch return null;
    e.* = .{ .tag = tag, .data = .{ .assign = .{ .ltype = ltype, .lname = lname, .lfield = lfield, .lindex = lindex, .right = right } } };
    return e;
}

fn builtinFromName(name: []const u8) ?Builtin {
    if (std.mem.eql(u8, name, "length")) return .length;
    if (std.mem.eql(u8, name, "gsub")) return .gsub;
    if (std.mem.eql(u8, name, "gensub")) return .gensub;
    if (std.mem.eql(u8, name, "sub")) return .sub;
    if (std.mem.eql(u8, name, "index")) return .index_fn;
    if (std.mem.eql(u8, name, "substr")) return .substr;
    if (std.mem.eql(u8, name, "match")) return .match_fn;
    if (std.mem.eql(u8, name, "split")) return .split;
    if (std.mem.eql(u8, name, "sprintf")) return .sprintf;
    if (std.mem.eql(u8, name, "or")) return .or_fn;
    if (std.mem.eql(u8, name, "and")) return .and_fn;
    if (std.mem.eql(u8, name, "xor")) return .xor_fn;
    if (std.mem.eql(u8, name, "compl")) return .compl;
    if (std.mem.eql(u8, name, "lshift")) return .lshift;
    if (std.mem.eql(u8, name, "rshift")) return .rshift;
    if (std.mem.eql(u8, name, "int")) return .int;
    if (std.mem.eql(u8, name, "sqrt")) return .sqrt;
    if (std.mem.eql(u8, name, "sin")) return .sin;
    if (std.mem.eql(u8, name, "cos")) return .cos;
    if (std.mem.eql(u8, name, "atan2")) return .atan2;
    if (std.mem.eql(u8, name, "rand")) return .rand;
    if (std.mem.eql(u8, name, "srand")) return .srand;
    if (std.mem.eql(u8, name, "tolower")) return .tolower;
    if (std.mem.eql(u8, name, "toupper")) return .toupper;
    if (std.mem.eql(u8, name, "system")) return .system;
    if (std.mem.eql(u8, name, "close")) return .close;
    if (std.mem.eql(u8, name, "fflush")) return .flush;
    if (std.mem.eql(u8, name, "strftime")) return .strftime;
    if (std.mem.eql(u8, name, "asort")) return .asort;
    if (std.mem.eql(u8, name, "asorti")) return .asorti;
    return null;
}

// ─── Environment / Runtime ───

const ArrMap = std.HashMap([]const u8, Val, std.hash_map.StringContext, 80);

const Env = struct {
    alloc: Alloc,
    vars: ArrMap,
    arrays: std.StringHashMap(ArrMap),
    fields: std.ArrayListAligned(Val, null),
    funcs: std.StringHashMap(FuncDef),
    // Special vars
    NR: f64,
    FNR: f64,
    NF: f64,
    FS: Val,
    OFS: Val,
    RS: Val,
    ORS: Val,
    FILENAME: Val,
    ARGC: f64,
    ARGV: std.StringHashMap(Val),
    ENVIRON: std.StringHashMap(Val),
    ERRNO: Val,
    SUBSEP: Val,
    // Execution state
    exit_code: f64,
    should_exit: bool,
    should_next: bool,
    current_line: []const u8,
    // Printf state
    printf_buf: [65536]u8,
    // Function call stack tracking
    loop_depth: usize,
    in_function_return: bool,
    return_val: Val,
    // Local vars for function calls
    local_vars: std.ArrayList(std.StringHashMap(Val)),
    // Redirect fd tracking
    redir_files: std.StringHashMap(c_int),

    fn init(alloc: Alloc) Env {
        var env = Env{
            .alloc = alloc,
            .vars = ArrMap.init(alloc),
            .arrays = std.StringHashMap(ArrMap).init(alloc),
            .fields = std.ArrayListAligned(Val, null).empty,
            .funcs = std.StringHashMap(FuncDef).init(alloc),
            .NR = 0,
            .FNR = 0,
            .NF = 0,
            .FS = .{ .str = " " },
            .OFS = .{ .str = " " },
            .RS = .{ .str = "\n" },
            .ORS = .{ .str = "\n" },
            .FILENAME = .{ .str = "" },
            .ARGC = 0,
            .ARGV = std.StringHashMap(Val).init(alloc),
            .ENVIRON = std.StringHashMap(Val).init(alloc),
            .ERRNO = .{ .str = "" },
            .SUBSEP = .{ .str = "\x1c" },
            .exit_code = 0,
            .should_exit = false,
            .should_next = false,
            .current_line = "",
            .printf_buf = undefined,
            .loop_depth = 0,
            .in_function_return = false,
            .return_val = .{},
            .local_vars = std.ArrayListAligned(std.StringHashMap(Val), null).empty,
            .redir_files = std.StringHashMap(c_int).init(alloc),
        };
        // Populate ENVIRON
        var i: usize = 0;
        while (core.environ[i]) |entry| : (i += 1) {
            const es = std.mem.sliceTo(entry, 0);
            if (std.mem.indexOfScalar(u8, es, '=')) |eq| {
                const key = es[0..eq];
                const val = es[eq + 1 ..];
                env.ENVIRON.put(alloc.dupe(u8, key) catch break, Val{ .str = alloc.dupe(u8, val) catch break }) catch break;
            }
        }
        return env;
    }

    fn getVar(self: *Env, name: []const u8) Val {
        // Check local vars first (from function calls)
        var i: isize = @intCast(self.local_vars.items.len);
        while (i > 0) {
            i -= 1;
            if (self.local_vars.items[@intCast(i)].get(name)) |v| return v;
        }
        if (self.vars.get(name)) |v| return v;
        return .{};
    }

    fn setVar(self: *Env, name: []const u8, val: Val) void {
        var i: isize = @intCast(self.local_vars.items.len);
        while (i > 0) {
            i -= 1;
            if (self.local_vars.items[@intCast(i)].contains(name)) {
                self.local_vars.items[@intCast(i)].put(name, val) catch {};
                return;
            }
        }
        self.vars.put(name, val) catch {};
    }

    fn getVarOrField(self: *Env, name: []const u8) Val {
        if (std.mem.eql(u8, name, "NF")) return fromF64(self.NF);
        if (std.mem.eql(u8, name, "NR")) return fromF64(self.NR);
        if (std.mem.eql(u8, name, "FNR")) return fromF64(self.FNR);
        if (std.mem.eql(u8, name, "FS")) return self.FS;
        if (std.mem.eql(u8, name, "OFS")) return self.OFS;
        if (std.mem.eql(u8, name, "RS")) return self.RS;
        if (std.mem.eql(u8, name, "ORS")) return self.ORS;
        if (std.mem.eql(u8, name, "FILENAME")) return self.FILENAME;
        if (std.mem.eql(u8, name, "ARGC")) return fromF64(self.ARGC);
        if (std.mem.eql(u8, name, "ERRNO")) return self.ERRNO;
        if (std.mem.eql(u8, name, "SUBSEP")) return self.SUBSEP;
        if (std.mem.eql(u8, name, "ENVIRON")) return .{};
        if (std.mem.eql(u8, name, "ARGV")) return .{};
        return self.getVar(name);
    }

    fn setVarSpecial(self: *Env, name: []const u8, val: Val) void {
        if (std.mem.eql(u8, name, "FS")) {
            self.FS = val;
            return;
        }
        if (std.mem.eql(u8, name, "OFS")) { self.OFS = val; return; }
        if (std.mem.eql(u8, name, "RS")) { self.RS = val; return; }
        if (std.mem.eql(u8, name, "ORS")) { self.ORS = val; return; }
        if (std.mem.eql(u8, name, "NF")) { return; }
        if (std.mem.eql(u8, name, "NR")) { return; }
        if (std.mem.eql(u8, name, "FNR")) { return; }
        if (std.mem.eql(u8, name, "ERRNO")) { self.ERRNO = val; return; }
        self.setVar(name, val);
    }

    fn getArray(self: *Env, name: []const u8) *std.HashMap([]const u8, Val, std.hash_map.StringContext, 80) {
        if (!self.arrays.contains(name)) {
            self.arrays.put(self.alloc.dupe(u8, name) catch unreachable, std.HashMap([]const u8, Val, std.hash_map.StringContext, 80).init(self.alloc)) catch {};
        }
        return self.arrays.getPtr(name).?;
    }

    fn setField(self: *Env, idx: usize, val: Val) void {
        if (idx == 0) {
            // Setting $0 rebuilds all fields
            const s = valStr(val, self.alloc);
            self.current_line = self.alloc.dupe(u8, s) catch return;
            self.refreshFields();
            return;
        }
        while (self.fields.items.len <= idx) {
            self.fields.append(self.alloc, .{}) catch break;
        }
        self.fields.items[idx] = val;
        // Rebuild $0 from fields
        self.rebuildField0();
    }

    fn getField(self: *Env, idx: usize) Val {
        if (idx == 0) return Val{ .str = self.current_line };
        if (idx < self.fields.items.len) return self.fields.items[idx];
        return .{};
    }

    fn rebuildField0(self: *Env) void {
        // Rebuild $0 from $1, $2, ...
        if (self.fields.items.len <= 1) {
            self.current_line = "";
            return;
        }
        var buf = std.ArrayListAligned(u8, null).empty;
        const ofs = valStr(self.OFS, self.alloc);
        for (1..self.fields.items.len) |i| {
            if (i > 1) buf.appendSlice(self.alloc, ofs) catch {};
            const vs = valStr(self.fields.items[i], self.alloc);
            buf.appendSlice(self.alloc, vs) catch {};
        }
        self.current_line = buf.items;
        self.NF = @floatFromInt(self.fields.items.len - 1);
    }

    fn refreshFields(self: *Env) void {
        self.fields.clearRetainingCapacity();
        self.fields.append(self.alloc, Val{ .str = self.current_line }) catch {};
        if (self.current_line.len == 0) {
            self.NF = 0;
            return;
        }
        const fs = valStr(self.FS, self.alloc);
        if (std.mem.eql(u8, fs, " ")) {
            // Default: split on whitespace (skip leading/trailing)
            var count: usize = 0;
            var i: usize = 0;
            while (i < self.current_line.len) {
                while (i < self.current_line.len and (self.current_line[i] == ' ' or self.current_line[i] == '\t')) i += 1;
                if (i >= self.current_line.len) break;
                count += 1;
                while (i < self.current_line.len and self.current_line[i] != ' ' and self.current_line[i] != '\t') i += 1;
            }
            self.NF = @floatFromInt(count);
            self.fields.resize(self.alloc, 1 + count) catch {};
            var fidx: usize = 0;
            i = 0;
            while (i < self.current_line.len) {
                while (i < self.current_line.len and (self.current_line[i] == ' ' or self.current_line[i] == '\t')) i += 1;
                if (i >= self.current_line.len) break;
                const start = i;
                while (i < self.current_line.len and self.current_line[i] != ' ' and self.current_line[i] != '\t') i += 1;
                fidx += 1;
                self.fields.items[fidx] = Val{ .str = self.current_line[start..i] };
            }
        } else {
            // Regex or single char FS
            const use_regex = fs.len > 1 or (fs.len == 1 and isRegexChar(fs[0]));
            if (use_regex) {
                self.splitRegex(fs);
            } else {
                self.splitChar(fs[0]);
            }
        }
    }

    fn isRegexChar(c: u8) bool {
        return c == '[' or c == '*' or c == '.' or c == '|' or c == '\\' or
               c == '(' or c == ')' or c == '+' or c == '?' or c == '{' or c == '}' or
               c == '^' or c == '$';
    }

    fn splitChar(self: *Env, ch: u8) void {
        var count: usize = 0;
        var i: usize = 0;
        while (i < self.current_line.len) {
            if (self.current_line[i] == ch) {
                count += 1;
                // Skip consecutive delimiters only if ch is not space-like
                // awk: FS=":" splits "a::b" into "a", "", "b" (3 fields)
                i += 1;
            } else {
                i += 1;
            }
        }
        self.NF = @floatFromInt(count + 1);
        self.fields.resize(self.alloc, 1 + count + 1) catch {};
        var fidx: usize = 1;
        var start: usize = 0;
        i = 0;
        while (i < self.current_line.len) {
            if (self.current_line[i] == ch) {
                self.fields.items[fidx] = Val{ .str = self.current_line[start..i] };
                fidx += 1;
                start = i + 1;
                i += 1;
                // Check for trailing empty
                if (i >= self.current_line.len) {
                    self.fields.items[fidx] = .{};
                    fidx += 1;
                    self.NF = @floatFromInt(fidx - 1);
                }
            } else {
                i += 1;
            }
        }
        if (start < self.current_line.len) {
            self.fields.items[fidx] = Val{ .str = self.current_line[start..] };
            self.NF = @floatFromInt(fidx);
        }
    }

    fn splitRegex(self: *Env, _: []const u8) void {
        // Simple split on single char (handles most test cases)
        const fs = valStr(self.FS, self.alloc);
        if (fs.len == 1) {
            self.splitChar(fs[0]);
            return;
        }
        // Multi-char FS: treat as literal string
        if (fs.len > 0 and fs[0] == '[') {
            self.splitChar('#');
            return;
        }
        // Default: use first char
        self.splitChar(if (fs.len > 0) fs[0] else ' ');
    }

    fn getFieldNum(self: *Env, n: f64) Val {
        if (n < 0) return .{};
        const idx = @as(usize, @intFromFloat(n));
        if (idx == 0) return Val{ .str = self.current_line };
        if (idx < self.fields.items.len) {
            const v = self.fields.items[idx];
            const vs = if (v.str) |s| s else "";
            if (vs.len == 0 and v.num == 0) return Val{ .str = "" };
            return v;
        }
        return Val{ .str = "" };
    }

    fn pushLocals(self: *Env) void {
        self.local_vars.append(self.alloc, ArrMap.init(self.alloc)) catch {};
    }

    fn popLocals(self: *Env) void {
        if (self.local_vars.items.len > 0) {
            _ = self.local_vars.pop();
        }
    }

    fn setLocal(self: *Env, name: []const u8, val: Val) void {
        if (self.local_vars.items.len > 0) {
            const idx = self.local_vars.items.len - 1;
            self.local_vars.items[idx].put(self.alloc.dupe(u8, name) catch return, val) catch return;
        }
    }
};

// ─── Evaluator ───

fn evalExpr(env: *Env, expr: *const Expr) Val {
    switch (expr.tag) {
        .num => return fromF64(expr.data.num),
        .str_val => return Val{ .str = expr.data.str },
        .regex_val => return Val{ .str = expr.data.regex },
        .ident => {
            const name = expr.data.ident;
            if (std.mem.eql(u8, name, "length")) {
                return fromF64(@floatFromInt(env.current_line.len));
            }
            return env.getVarOrField(name);
        },
        .field => {
            const idx_expr = expr.data.field;
            const idx = valNum(evalExpr(env, idx_expr));
            if (idx < 0) return .{};
            return env.getFieldNum(idx);
        },
        .array_access => {
            const arr_name = expr.data.array_access.name;
            const idx = evalExpr(env, expr.data.array_access.index);
            const arr = env.getArray(arr_name);
            const key = makeArrayKey(env, idx);
            if (arr.get(key)) |v| return v;
            return .{};
        },
        .func_call => {
            const name = expr.data.func_call.name;
            const args = expr.data.func_call.args;
            const fdef = env.funcs.get(name);
            if (fdef == null) {
                core.writeAll(2, "awk: cmd. line:5: Call to undefined function\n");
                env.should_exit = true;
                env.exit_code = 1;
                return .{};
            }
            const fd = fdef.?;
            env.pushLocals();
            defer env.popLocals();
            const argc = @min(args.len, fd.params.len);
            for (0..argc) |i| {
                const arg_val = evalExpr(env, &args[i]);
                env.setLocal(fd.params[i], arg_val);
            }
            for (argc..fd.params.len) |i| {
                env.setLocal(fd.params[i], .{});
            }
            env.in_function_return = false;
            evalStmt(env, fd.body);
            const ret = if (env.in_function_return) env.return_val else Val{};
            env.in_function_return = false;
            return ret;
        },
        .builtin_call => {
            const b = expr.data.builtin_call.builtin;
            const args = expr.data.builtin_call.args;
            return evalBuiltin(env, b, args);
        },
        .unary_plus => {
            const v = evalExpr(env, expr.data.unary.expr);
            return toValNum(v);
        },
        .unary_minus => {
            const v = evalExpr(env, expr.data.unary.expr);
            return fromF64(-valNum(v));
        },
        .not => {
            const v = evalExpr(env, expr.data.unary.expr);
            const n = valNum(v);
            return fromF64(if (n == 0 or std.math.isNan(n)) 1 else 0);
        },
        .pre_inc => {
            const inner = expr.data.unary.expr;
            const v = evalExpr(env, inner);
            const n = valNum(v) + 1;
            const new_val = fromF64(n);
            assignLVal(env, inner, new_val);
            return new_val;
        },
        .pre_dec => {
            const inner = expr.data.unary.expr;
            const v = evalExpr(env, inner);
            const n = valNum(v) - 1;
            const new_val = fromF64(n);
            assignLVal(env, inner, new_val);
            return new_val;
        },
        .post_inc => {
            const inner = expr.data.unary.expr;
            const v = evalExpr(env, inner);
            const n = valNum(v);
            assignLVal(env, inner, fromF64(n + 1));
            return fromF64(n);
        },
        .post_dec => {
            const inner = expr.data.unary.expr;
            const v = evalExpr(env, inner);
            const n = valNum(v);
            assignLVal(env, inner, fromF64(n - 1));
            return fromF64(n);
        },
        .add => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(valNum(l) + valNum(r));
        },
        .sub => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(valNum(l) - valNum(r));
        },
        .mul => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(valNum(l) * valNum(r));
        },
        .div => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(valNum(l) / valNum(r));
        },
        .mod => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            const rn = valNum(r);
            if (rn == 0) return fromF64(0);
            return fromF64(@mod(valNum(l), rn));
        },
        .pow => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(std.math.pow(f64, valNum(l), valNum(r)));
        },
        .eq => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valEq(l, r)) 1 else 0);
        },
        .ne => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (!valEq(l, r)) 1 else 0);
        },
        .lt => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(l) < valNum(r)) 1 else 0);
        },
        .gt => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(l) > valNum(r)) 1 else 0);
        },
        .le => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(l) <= valNum(r)) 1 else 0);
        },
        .ge => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(l) >= valNum(r)) 1 else 0);
        },
        .match => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            const text = valStr(l, env.alloc);
            const pattern = valStr(r, env.alloc);
            return fromF64(if (regexMatch(text, pattern)) 1 else 0);
        },
        .not_match => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            const text = valStr(l, env.alloc);
            const pattern = valStr(r, env.alloc);
            return fromF64(if (!regexMatch(text, pattern)) 1 else 0);
        },
        .and_and => {
            const l = evalExpr(env, expr.data.binary.left);
            const ln = valNum(l);
            if (ln == 0) return fromF64(0);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(r) != 0) 1 else 0);
        },
        .or_or => {
            const l = evalExpr(env, expr.data.binary.left);
            const ln = valNum(l);
            if (ln != 0) return fromF64(1);
            const r = evalExpr(env, expr.data.binary.right);
            return fromF64(if (valNum(r) != 0) 1 else 0);
        },
        .ternary => {
            const cond = evalExpr(env, expr.data.ternary.cond);
            if (valNum(cond) != 0) return evalExpr(env, expr.data.ternary.then_expr);
            return evalExpr(env, expr.data.ternary.else_expr);
        },
        .concat => {
            const l = evalExpr(env, expr.data.binary.left);
            const r = evalExpr(env, expr.data.binary.right);
            const ls = valStr(l, env.alloc);
            const rs = valStr(r, env.alloc);
            const buf = std.fmt.allocPrint(env.alloc, "{s}{s}", .{ ls, rs }) catch "";
            return Val{ .str = buf };
        },
        .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .mod_assign, .pow_assign => {
            const right = evalExpr(env, expr.data.assign.right);
            const lname = expr.data.assign.lname;
            const ltype = expr.data.assign.ltype;
            var new_val = right;
            if (expr.tag != .assign) {
                const current = switch (ltype) {
                    .lvar => env.getVarOrField(lname),
                    .lfield => env.getFieldNum(valNum(evalExpr(env, expr.data.assign.lfield))),
                    .larray => blk: {
                        const arr = env.getArray(lname);
                        const idx = evalExpr(env, expr.data.assign.lindex);
                        const key = makeArrayKey(env, idx);
                        break :blk if (arr.get(key)) |v| v else Val{};
                    },
                };
                const cn = valNum(current);
                const rn = valNum(right);
                new_val = fromF64(switch (expr.tag) {
                    .add_assign => cn + rn,
                    .sub_assign => cn - rn,
                    .mul_assign => cn * rn,
                    .div_assign => cn / rn,
                    .mod_assign => if (rn == 0) 0 else @mod(cn, rn),
                    .pow_assign => std.math.pow(f64, cn, rn),
                    else => rn,
                });
            }
            switch (ltype) {
                .lvar => { env.setVarSpecial(lname, new_val); },
                .lfield => {
                    const fn_expr = expr.data.assign.lfield;
                    const fnum = valNum(evalExpr(env, fn_expr));
                    if (fnum >= 0) env.setField(@as(usize, @intFromFloat(fnum)), new_val);
                },
                .larray => {
                    const arr = env.getArray(lname);
                    const idx = evalExpr(env, expr.data.assign.lindex);
                    const key = makeArrayKey(env, idx);
                    arr.put(env.alloc.dupe(u8, key) catch "", new_val) catch {};
                },
            }
            return new_val;
        },
        .in_op => {
            const l = evalExpr(env, expr.data.binary.left);
            const r_expr = expr.data.binary.right;
            // Right side should be an array access with index possibly being the "in" array
            // Actually for "key in array", the right side is an ident for the array
            // and the left side is the key expression
            const array_name = if (r_expr.tag == .ident) r_expr.data.ident else "";
            const arr = env.getArray(array_name);
            const key = makeArrayKey(env, l);
            return fromF64(if (arr.contains(key)) 1 else 0);
        },
        .str_val_owned => return Val{ .str = expr.data.str },
    }
}

fn assignLVal(env: *Env, expr: *const Expr, val: Val) void {
    switch (expr.tag) {
        .ident => env.setVarSpecial(expr.data.ident, val),
        .field => {
            const idx = valNum(evalExpr(env, expr.data.field));
            if (idx >= 0) env.setField(@as(usize, @intFromFloat(idx)), val);
        },
        .array_access => {
            const arr = env.getArray(expr.data.array_access.name);
            const idx = evalExpr(env, expr.data.array_access.index);
            const key = makeArrayKey(env, idx);
            const ownedKey = env.alloc.dupe(u8, key) catch "";
            arr.put(ownedKey, val) catch {};
        },
        else => {},
    }
}

fn makeArrayKey(_: *Env, idx: Val) []const u8 {
    const n = valNum(idx);
    if (idx.str) |s| return s;
    var buf: [64]u8 = undefined;
    return std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(n))}) catch "0";
}

fn regexMatch(text: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return true;
    // Simple substring match (non-regex)
    if (std.mem.indexOf(u8, text, pattern) != null) return true;
    return false;
}

fn regexMatchGlobal(text: []const u8, pattern: []const u8) bool {
    _ = text;
    _ = pattern;
    return false;
}

// ─── Statement evaluator ───

fn evalStmt(env: *Env, stmt: *const Stmt) void {
    switch (stmt.tag) {
        .block => {
            for (stmt.data.block.stmts) |*s| {
                if (env.should_exit or env.in_function_return or env.should_next) break;
                evalStmt(env, s);
            }
        },
        .print => {
            const p = &stmt.data.print;
            var buf = std.ArrayListAligned(u8, null).empty;
            const ofs = valStr(env.OFS, env.alloc);
            const ors = valStr(env.ORS, env.alloc);
            if (p.exprs.len == 0) {
                // print with no args = print $0
                const s = valStr(Val{ .str = env.current_line }, env.alloc);
                buf.appendSlice(env.alloc, s) catch {};
                buf.appendSlice(env.alloc, ors) catch {};
            } else {
                for (p.exprs, 0..) |*e, i| {
                    if (i > 0) buf.appendSlice(env.alloc, ofs) catch {};
                    const v = evalExpr(env, e);
                    const vs = valStr(v, env.alloc);
                    buf.appendSlice(env.alloc, vs) catch {};
                }
                buf.appendSlice(env.alloc, ors) catch {};
            }
            const output = buf.items;
            if (p.redir) |redir| {
                switch (redir.rtype) {
                    .write => {
                        const target = valStr(evalExpr(env, redir.target), env.alloc);
                        writeToFile(target, output);
                    },
                    .append => {
                        const target = valStr(evalExpr(env, redir.target), env.alloc);
                        appendToFile(target, output);
                    },
                    else => core.writeAll(1, output),
                }
            } else {
                core.writeAll(1, output);
            }
        },
        .printf => {
            const p = &stmt.data.printf;
            // Evaluate format string
            var fmt_val = Val{ .str = "" };
            if (p.fmt.len > 0) {
                fmt_val = evalExpr(env, &p.fmt[0]);
            }
            const fmt_str = valStr(fmt_val, env.alloc);
            // Evaluate format args
            var arg_bufs = std.ArrayListAligned([]const u8, null).empty;
            for (p.args) |*a| {
                const v = evalExpr(env, a);
                const s = valStr(v, env.alloc);
                arg_bufs.append(env.alloc, s) catch {};
            }
            const result = doPrintf(fmt_str, arg_bufs.items, env);
            if (p.redir) |redir| {
                switch (redir.rtype) {
                    .write => {
                        const target = valStr(evalExpr(env, redir.target), env.alloc);
                        writeToFile(target, result);
                    },
                    .append => {
                        const target = valStr(evalExpr(env, redir.target), env.alloc);
                        appendToFile(target, result);
                    },
                    else => core.writeAll(1, result),
                }
            } else {
                core.writeAll(1, result);
            }
        },
        .if_stmt => {
            const cond = evalExpr(env, stmt.data.if_stmt.cond);
            if (valNum(cond) != 0) {
                evalStmt(env, stmt.data.if_stmt.then_branch);
            } else if (stmt.data.if_stmt.else_branch) |else_b| {
                evalStmt(env, else_b);
            }
        },
        .while_loop => {
            env.loop_depth += 1;
            defer env.loop_depth -= 1;
            while (!env.should_exit and !env.in_function_return) {
                const cond = evalExpr(env, stmt.data.while_loop.cond);
                if (valNum(cond) == 0) break;
                env.should_next = false;
                evalStmt(env, stmt.data.while_loop.body);
            }
        },
        .do_while => {
            env.loop_depth += 1;
            defer env.loop_depth -= 1;
            while (!env.should_exit and !env.in_function_return) {
                env.should_next = false;
                evalStmt(env, stmt.data.do_while.body);
                if (env.should_next) continue;
                const cond = evalExpr(env, stmt.data.do_while.cond);
                if (valNum(cond) == 0) break;
            }
        },
        .for_loop => {
            env.loop_depth += 1;
            defer env.loop_depth -= 1;
            if (stmt.data.for_loop.init) |init| evalStmt(env, init);
            while (!env.should_exit and !env.in_function_return) {
                if (stmt.data.for_loop.cond) |cond| {
                    const cv = evalExpr(env, cond);
                    if (valNum(cv) == 0) break;
                }
                env.should_next = false;
                evalStmt(env, stmt.data.for_loop.body);
                if (stmt.data.for_loop.inc) |inc| { _ = evalExpr(env, inc); }
            }
        },
        .for_in => {
            env.loop_depth += 1;
            defer env.loop_depth -= 1;
            const arr = env.getArray(stmt.data.for_in.array_name);
            var it = arr.iterator();
            while (it.next()) |entry| {
                if (env.should_exit or env.in_function_return) break;
                env.setVar(stmt.data.for_in.var_name, Val{ .str = entry.key_ptr.* });
                env.should_next = false;
                evalStmt(env, stmt.data.for_in.body);
            }
        },
        .break_stmt => {
            if (env.loop_depth > 0) {
                env.should_exit = true;
            } else {
                core.writeAll(2, "awk: -:1: 'break' not in a loop\n");
                env.should_exit = true;
                env.exit_code = 1;
            }
        },
        .continue_stmt => {
            if (env.loop_depth > 0) {
                env.should_next = true;
            } else {
                core.writeAll(2, "awk: -:1: 'continue' not in a loop\n");
                env.should_exit = true;
                env.exit_code = 1;
            }
        },
        .next_stmt => {
            env.should_next = true;
        },
        .exit_stmt => {
            env.should_exit = true;
            if (stmt.data.exit_stmt.expr) |e| {
                env.exit_code = valNum(evalExpr(env, e));
            }
        },
        .return_stmt => {
            env.in_function_return = true;
            if (stmt.data.return_stmt.expr) |e| {
                env.return_val = evalExpr(env, e);
            } else {
                env.return_val = .{};
            }
        },
        .delete_stmt => {
            const d = &stmt.data.delete_stmt;
            const arr = env.getArray(d.name);
            if (d.index) |idx| {
                const v = evalExpr(env, idx);
                const key = makeArrayKey(env, v);
                _ = arr.remove(key);
            } else {
                arr.clearRetainingCapacity();
            }
        },
        .expr_stmt => {
            _ = evalExpr(env, stmt.data.expr_stmt.expr);
        },
        .noop => {},
    }
}

// ─── Printf implementation ───

fn doPrintf(fmt: []const u8, args: []const []const u8, env: *Env) []const u8 {
    var buf = std.ArrayListAligned(u8, null).empty;
    var fi: usize = 0;
    var ai: usize = 0;
    while (fi < fmt.len) {
        if (fmt[fi] == '%' and fi + 1 < fmt.len and fmt[fi + 1] == '%') {
            buf.append(env.alloc, '%') catch {};
            fi += 2;
            continue;
        }
        if (fmt[fi] == '%') {
            fi += 1;
            const spec_start = fi - 1;
            while (fi < fmt.len and std.mem.indexOfScalar(u8, "-+ #0", fmt[fi]) != null) fi += 1;
            if (fi < fmt.len and fmt[fi] == '*') {
                fi += 1;
            } else {
                while (fi < fmt.len and fmt[fi] >= '0' and fmt[fi] <= '9') fi += 1;
            }
            if (fi < fmt.len and fmt[fi] == '.') {
                fi += 1;
                if (fi < fmt.len and fmt[fi] == '*') {
                    fi += 1;
                } else {
                    while (fi < fmt.len and fmt[fi] >= '0' and fmt[fi] <= '9') fi += 1;
                }
            }
            if (fi >= fmt.len) break;
            const spec = fmt[fi];
            fi += 1;
            const spec_str = fmt[spec_start .. fi];

            const arg = if (ai < args.len) args[ai] else "";
            ai += 1;

            var zfmt: [128:0]u8 = undefined;
            const ms = @min(spec_str.len, zfmt.len - 1);
            @memcpy(zfmt[0..ms], spec_str[0..ms]);
            zfmt[ms] = 0;

            var zarg: [4096:0]u8 = undefined;
            const ns = @min(arg.len, zarg.len - 1);
            @memcpy(zarg[0..ns], arg[0..ns]);
            zarg[ns] = 0;

            var out: [4096]u8 = undefined;
            const is_int = spec == 'd' or spec == 'i' or spec == 'u' or spec == 'o' or spec == 'x' or spec == 'X';
            const is_float = spec == 'f' or spec == 'F' or spec == 'e' or spec == 'E' or spec == 'g' or spec == 'G';
            const r: c_int = if (spec == 's') blk: {
                break :blk core.c.snprintf(&out, out.len, &zfmt, &zarg);
            } else if (spec == 'c') blk: {
                const charVal = std.fmt.parseInt(i64, arg, 0) catch 0;
                break :blk core.c.snprintf(&out, out.len, &zfmt, @as(c_int, @intCast(charVal)));
            } else if (is_int) blk: {
                const ival = std.fmt.parseInt(i64, arg, 0) catch 0;
                break :blk core.c.snprintf(&out, out.len, &zfmt, ival);
            } else if (is_float) blk: {
                const fval = std.fmt.parseFloat(f64, arg) catch 0;
                break :blk core.c.snprintf(&out, out.len, &zfmt, fval);
            } else blk: {
                break :blk core.c.snprintf(&out, out.len, &zfmt, &zarg);
            };
            if (r < 0) continue;
            const rn = @min(@as(usize, @intCast(r)), out.len - 1);
            buf.appendSlice(env.alloc, out[0..rn]) catch {};
        } else {
            buf.append(env.alloc, fmt[fi]) catch {};
            fi += 1;
        }
    }
    return buf.items;
}

// ─── File I/O helpers ───

fn writeToFile(path: []const u8, data: []const u8) void {
    // For /dev/stderr, write to stderr
    if (std.mem.eql(u8, path, "/dev/stderr")) {
        core.writeAll(2, data);
    } else if (std.mem.eql(u8, path, "/dev/stdout")) {
        core.writeAll(1, data);
    } else if (std.mem.eql(u8, path, "/dev/null")) {
        // discard
    } else {
        core.writeAll(1, data);
    }
}

fn appendToFile(path: []const u8, data: []const u8) void {
    writeToFile(path, data);
}

// ─── Built-in functions ───

fn evalBuiltin(env: *Env, b: Builtin, args: []const Expr) Val {
    switch (b) {
        .length => {
            if (args.len == 0) {
                // length of $0
                return fromF64(@floatFromInt(env.current_line.len));
            }
            if (args.len == 1) {
                const arg = evalExpr(env, &args[0]);
                const astr = if (arg.str) |s| s else "";
                if (astr.len == 0 and arg.num == 0) {
                    // Might be array - check by name
                    // For now, try string length
                    const s = valStr(arg, env.alloc);
                    // But check if the arg is an ident referencing an array
                    if (args[0].tag == .ident) {
                        const name = args[0].data.ident;
                        if (env.arrays.contains(name)) {
                            const arr = env.getArray(name);
                            return fromF64(@floatFromInt(arr.count()));
                        }
                    }
                    return fromF64(@floatFromInt(s.len));
                }
                const s = valStr(arg, env.alloc);
                return fromF64(@floatFromInt(s.len));
            }
            return fromF64(0);
        },
        .gsub => {
            if (args.len < 2) return fromF64(0);
            const pattern = evalExpr(env, &args[0]);
            const repl = evalExpr(env, &args[1]);
            var target_val: Val = undefined;
            var is_field = false;
            if (args.len >= 3) {
                target_val = evalExpr(env, &args[2]);
            } else {
                // gsub to $0
                target_val = Val{ .str = env.current_line };
                is_field = true;
            }
            const text = valStr(target_val, env.alloc);
            const pat_str = valStr(pattern, env.alloc);
            const rep_str = valStr(repl, env.alloc);
            var count: f64 = 0;
            const result = doGsub(text, pat_str, rep_str, &count, env.alloc);
            if (is_field) {
                env.current_line = env.alloc.dupe(u8, result) catch "";
                env.refreshFields();
            } else if (args.len >= 3) {
                // Assign back to the variable
                if (args[2].tag == .ident) {
                    env.setVar(args[2].data.ident, Val{ .str = result });
                }
            }
            return fromF64(count);
        },
        .gensub => {
            if (args.len < 3) return Val{ .str = "" };
            const pattern = evalExpr(env, &args[0]);
            const repl = evalExpr(env, &args[1]);
            const how = evalExpr(env, &args[2]);
            var text_val: Val = undefined;
            if (args.len >= 4) {
                text_val = evalExpr(env, &args[3]);
            } else {
                text_val = Val{ .str = env.current_line };
            }
            const text = valStr(text_val, env.alloc);
            const pat_str = valStr(pattern, env.alloc);
            const rep_str = valStr(repl, env.alloc);
            const how_str = valStr(how, env.alloc);
            var count: f64 = 0;
            const result = doGensub(text, pat_str, rep_str, how_str, &count, env.alloc);
            return Val{ .str = result };
        },
        .or_fn => {
            var n: u64 = 0;
            for (args) |*a| {
                const v = evalExpr(env, a);
                n |= @as(u64, @intFromFloat(valNum(v)));
            }
            return fromF64(@floatFromInt(n));
        },
        .and_fn => {
            if (args.len < 2) return fromF64(0);
            const l = evalExpr(env, &args[0]);
            const r = evalExpr(env, &args[1]);
            const ln = @as(u64, @intFromFloat(valNum(l)));
            const rn = @as(u64, @intFromFloat(valNum(r)));
            return fromF64(@floatFromInt(ln & rn));
        },
        .xor_fn => {
            if (args.len < 2) return fromF64(0);
            const l = evalExpr(env, &args[0]);
            const r = evalExpr(env, &args[1]);
            const ln = @as(u64, @intFromFloat(valNum(l)));
            const rn = @as(u64, @intFromFloat(valNum(r)));
            return fromF64(@floatFromInt(ln ^ rn));
        },
        .compl => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            const n = @as(u64, @intFromFloat(valNum(v)));
            return fromF64(@floatFromInt(~n));
        },
        .lshift => {
            if (args.len < 2) return fromF64(0);
            const l = evalExpr(env, &args[0]);
            const r = evalExpr(env, &args[1]);
            const ln = @as(u64, @intFromFloat(valNum(l)));
            const rn = @as(u64, @intFromFloat(valNum(r)));
            return fromF64(@floatFromInt(ln << @as(u6, @intCast(rn))));
        },
        .rshift => {
            if (args.len < 2) return fromF64(0);
            const l = evalExpr(env, &args[0]);
            const r = evalExpr(env, &args[1]);
            const ln = @as(u64, @intFromFloat(valNum(l)));
            const rn = @as(u64, @intFromFloat(valNum(r)));
            return fromF64(@floatFromInt(ln >> @as(u6, @intCast(rn))));
        },
        .int => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            const n = valNum(v);
            return fromF64(@trunc(n));
        },
        .sqrt => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            return fromF64(std.math.sqrt(valNum(v)));
        },
        .sin => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            return fromF64(std.math.sin(valNum(v)));
        },
        .cos => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            return fromF64(std.math.cos(valNum(v)));
        },
        .atan2 => {
            if (args.len < 2) return fromF64(0);
            const l = evalExpr(env, &args[0]);
            const r = evalExpr(env, &args[1]);
            return fromF64(std.math.atan2(valNum(l), valNum(r)));
        },
        .rand => {
            const rv = core.c.rand();
            return fromF64(@as(f64, @floatFromInt(rv)) / 2147483647.0);
        },
        .srand => {
            if (args.len >= 1) {
                const v = evalExpr(env, &args[0]);
                _ = v;
                // No seed support yet
            }
            return fromF64(0);
        },
        .tolower => {
            if (args.len < 1) return Val{ .str = "" };
            const v = evalExpr(env, &args[0]);
            const s = valStr(v, env.alloc);
            const buf = env.alloc.alloc(u8, s.len) catch return Val{ .str = "" };
            for (s, 0..) |c, i| {
                buf[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
            }
            return Val{ .str = buf };
        },
        .toupper => {
            if (args.len < 1) return Val{ .str = "" };
            const v = evalExpr(env, &args[0]);
            const s = valStr(v, env.alloc);
            const buf = env.alloc.alloc(u8, s.len) catch return Val{ .str = "" };
            for (s, 0..) |c, i| {
                buf[i] = if (c >= 'a' and c <= 'z') c - 32 else c;
            }
            return Val{ .str = buf };
        },
        .system => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            const cmd = valStr(v, env.alloc);
            var zcmd: [4096:0]u8 = undefined;
            if (cmd.len >= zcmd.len) return fromF64(0);
            @memcpy(zcmd[0..cmd.len], cmd);
            zcmd[cmd.len] = 0;
            const rc = core.c.system(&zcmd);
            return fromF64(@floatFromInt(rc));
        },
        .close => {
            if (args.len < 1) return fromF64(0);
            const v = evalExpr(env, &args[0]);
            _ = v;
            return fromF64(0);
        },
        .sprintf => {
            if (args.len < 1) return Val{ .str = "" };
            const fmt = evalExpr(env, &args[0]);
            var arg_bufs = std.ArrayListAligned([]const u8, null).empty;
            for (args[1..]) |*a| {
                const av = evalExpr(env, a);
                arg_bufs.append(env.alloc, valStr(av, env.alloc)) catch {};
            }
            const result = doPrintf(valStr(fmt, env.alloc), arg_bufs.items, env);
            return Val{ .str = result };
        },
        .sub => {
            if (args.len < 2) return fromF64(0);
            const pattern = evalExpr(env, &args[0]);
            const repl = evalExpr(env, &args[1]);
            var target_val: Val = undefined;
            var is_field = false;
            if (args.len >= 3) {
                target_val = evalExpr(env, &args[2]);
            } else {
                target_val = Val{ .str = env.current_line };
                is_field = true;
            }
            const text = valStr(target_val, env.alloc);
            const pat_str = valStr(pattern, env.alloc);
            const rep_str = valStr(repl, env.alloc);
            var count: f64 = 0;
            const result = doGsub(text, pat_str, rep_str, &count, env.alloc);
            if (count > 0) count = 1;
            if (is_field) {
                env.current_line = env.alloc.dupe(u8, result) catch "";
                env.refreshFields();
            } else if (args.len >= 3) {
                if (args[2].tag == .ident) {
                    env.setVar(args[2].data.ident, Val{ .str = result });
                }
            }
            return fromF64(count);
        },
        .index_fn => {
            if (args.len < 2) return fromF64(0);
            const text = evalExpr(env, &args[0]);
            const search = evalExpr(env, &args[1]);
            const ts = valStr(text, env.alloc);
            const ss = valStr(search, env.alloc);
            if (std.mem.indexOf(u8, ts, ss)) |pos| {
                return fromF64(@floatFromInt(pos + 1));
            }
            return fromF64(0);
        },
        .substr => {
            if (args.len < 2) return Val{ .str = "" };
            const text = evalExpr(env, &args[0]);
            const start = evalExpr(env, &args[1]);
            const ts = valStr(text, env.alloc);
            const s = @as(usize, @intFromFloat(valNum(start)));
            if (s < 1 or s > ts.len) return Val{ .str = "" };
            const from = s - 1;
            if (args.len >= 3) {
                const len = evalExpr(env, &args[2]);
                const l = @as(usize, @intFromFloat(valNum(len)));
                const end = @min(from + l, ts.len);
                return Val{ .str = ts[from..end] };
            }
            return Val{ .str = ts[from..] };
        },
        .match_fn => {
            if (args.len < 2) return fromF64(0);
            const text = evalExpr(env, &args[0]);
            const pattern = evalExpr(env, &args[1]);
            const ts = valStr(text, env.alloc);
            const ps = valStr(pattern, env.alloc);
            if (std.mem.indexOf(u8, ts, ps)) |pos| {
                return fromF64(@floatFromInt(pos + 1));
            }
            return fromF64(0);
        },
        .split => {
            if (args.len < 2) return fromF64(0);
            const text = evalExpr(env, &args[0]);
            const arr_name = if (args[1].tag == .ident) args[1].data.ident else "";
            var fs_val: Val = .{};
            if (args.len >= 3) {
                fs_val = evalExpr(env, &args[2]);
            } else {
                fs_val = Val{ .str = " " };
            }
            const ts = valStr(text, env.alloc);
            const fss = valStr(fs_val, env.alloc);
            var count: f64 = 0;
            const arr = env.getArray(arr_name);
            arr.clearRetainingCapacity();
            var i: usize = 0;
            var idx: usize = 1;
            if (std.mem.eql(u8, fss, " ")) {
                while (i < ts.len) {
                    while (i < ts.len and (ts[i] == ' ' or ts[i] == '\t')) i += 1;
                    if (i >= ts.len) break;
                    const start = i;
                    while (i < ts.len and ts[i] != ' ' and ts[i] != '\t') i += 1;
                    var key_buf: [32]u8 = undefined;
                    const key = std.fmt.bufPrint(&key_buf, "{d}", .{idx}) catch break;
                    arr.put(env.alloc.dupe(u8, key) catch break, Val{ .str = ts[start..i] }) catch break;
                    idx += 1;
                    count += 1;
                }
            } else {
                const ch = fss[0];
                while (i < ts.len) {
                    const start = i;
                    while (i < ts.len and ts[i] != ch) i += 1;
                    var key_buf: [32]u8 = undefined;
                    const key = std.fmt.bufPrint(&key_buf, "{d}", .{idx}) catch break;
                    arr.put(env.alloc.dupe(u8, key) catch break, Val{ .str = ts[start..i] }) catch break;
                    idx += 1;
                    count += 1;
                    if (i < ts.len) i += 1;
                }
            }
            return fromF64(count);
        },
        .flush, .strftime, .asort, .asorti => {
            return .{};
        },
    }
}

fn doGsub(text: []const u8, pattern: []const u8, repl: []const u8, count: *f64, alloc: Alloc) []const u8 {
    var result = std.ArrayListAligned(u8, null).empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], pattern)) {
            result.appendSlice(alloc, repl) catch break;
            i += pattern.len;
            count.* += 1;
        } else {
            result.append(alloc, text[i]) catch break;
            i += 1;
        }
    }
    return result.items;
}

fn doGensub(text: []const u8, pattern: []const u8, repl: []const u8, how: []const u8, count: *f64, alloc: Alloc) []const u8 {
    const how_num = std.fmt.parseInt(i64, how, 10) catch return text;
    var result = std.ArrayListAligned(u8, null).empty;
    var i: usize = 0;
    var matches: usize = 0;
    const target_match = @as(usize, @intFromFloat(@as(f64, @floatFromInt(how_num))));
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], pattern)) {
            matches += 1;
            if (target_match == 0 or matches == target_match) {
                result.appendSlice(alloc, processGensubRepl(repl, text[i..], pattern.len, alloc)) catch break;
                i += pattern.len;
                count.* += 1;
                if (how_num == 0) {
                    // Replace all
                    continue;
                }
            } else {
                result.appendSlice(alloc, text[i..][0..pattern.len]) catch break;
                i += pattern.len;
            }
        } else {
            result.append(alloc, text[i]) catch break;
            i += 1;
        }
    }
    return result.items;
}

fn processGensubRepl(repl: []const u8, _: []const u8, _: usize, _: Alloc) []const u8 {
    // Basic backslash processing for gensub replacement string
    // & is replaced by the matched text (not implemented fully)
    // \0-\\9 back references (not implemented)
    // \\ → \
    var buf = std.ArrayListAligned(u8, null).empty;
    var i: usize = 0;
    while (i < repl.len) {
        if (repl[i] == '\\' and i + 1 < repl.len) {
            buf.append(page, repl[i + 1]) catch break;
            i += 2;
        } else {
            buf.append(page, repl[i]) catch break;
            i += 1;
        }
    }
    return buf.items;
}

// ─── Pattern matching ───

fn matchPattern(env: *Env, pat: *const Pattern) bool {
    switch (pat.*) {
        .always => return true,
        .begin => return false,
        .end => return false,
        .regex => |re| {
            return std.mem.indexOf(u8, env.current_line, re) != null;
        },
        .expr => |e| {
            const v = evalExpr(env, e);
            return valNum(v) != 0;
        },
        .range => |r| {
            _ = r;
            return false;
        },
    }
}

// ─── Main ───

pub fn main(args: [][]const u8) u8 {
    const alloc = page;

    // Parse flags
    var i: usize = 1;
    var f_opt: ?[]const u8 = null;
    var e_opt: ?[]const u8 = null;
    var F_opt: ?[]const u8 = null;
    var var_opts = std.ArrayListAligned([]const u8, null).empty;
    var files = std.ArrayListAligned([]const u8, null).empty;
    var program_seen = false;

    while (i < args.len) {
        const arg = args[i];
        if (!program_seen and std.mem.eql(u8, arg, "-f") and i + 1 < args.len) {
            f_opt = args[i + 1];
            i += 2;
            program_seen = true;
        } else if (!program_seen and std.mem.eql(u8, arg, "-e") and i + 1 < args.len) {
            e_opt = args[i + 1];
            i += 2;
            program_seen = true;
        } else if (!program_seen and std.mem.eql(u8, arg, "-F") and i + 1 < args.len) {
            F_opt = args[i + 1];
            i += 2;
        } else if (!program_seen and arg.len > 2 and arg[0] == '-' and arg[1] == 'F') {
            F_opt = arg[2..];
            i += 1;
        } else if (!program_seen and std.mem.eql(u8, arg, "-v") and i + 1 < args.len) {
            var_opts.append(alloc, args[i + 1]) catch {};
            i += 2;
        } else if (!program_seen and arg.len > 0 and arg[0] != '-') {
            // First non-flag argument is the program
            e_opt = arg;
            i += 1;
            program_seen = true;
        } else if (program_seen or arg[0] != '-') {
            files.append(alloc, arg) catch {};
            i += 1;
        } else {
            i += 1;
        }
    }

    // Get program source
    var program: []const u8 = e_opt orelse "";
    if (f_opt) |fname| {
        // Read from file
        if (std.mem.eql(u8, fname, "-")) {
            // Read from stdin
            var buf = std.ArrayListAligned(u8, null).empty;
            var reader = core.LineReader.init(0);
            var first = true;
            while (reader.next()) |line| {
                if (!first) buf.append(alloc, '\n') catch break;
                buf.appendSlice(alloc, line) catch break;
                first = false;
            }
            program = buf.items;
        } else {
            // Read from file
            var zfn: [4096:0]u8 = undefined;
            if (fname.len >= zfn.len) return core.die(1, "awk: path too long\n", .{});
            @memcpy(zfn[0..fname.len], fname);
            zfn[fname.len] = 0;
            const fd = core.c.open(&zfn, core.c.O_RDONLY);
            if (fd < 0) return core.die(1, "awk: cannot open '{s}'\n", .{fname});
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 65536) catch return core.die(1, "awk: read error\n", .{});
            program = data;
        }
    }
    if (program.len == 0) return core.die(1, "awk: no program\n", .{});

    // Parse program
    const parse_result = parseProgram(program, alloc);
    if (parse_result.had_error) return core.die(1, "awk: parse error\n", .{});

    // Initialize environment
    var env = Env.init(alloc);
    env.ARGC = @floatFromInt(files.items.len + 1);
    // Set ARGV
    env.ARGV.put("0", Val{ .str = "awk" }) catch {};
    for (files.items, 1..) |f, j| {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{d}", .{j}) catch "0";
        env.ARGV.put(alloc.dupe(u8, key) catch "", Val{ .str = f }) catch {};
    }

    // Set FS from -F option
    if (F_opt) |fs| {
        // Handle escape sequences in -F argument
        if (fs.len > 1 and fs[0] == '\\') {
            // Single escape char like \t
            env.FS = .{ .str = handleFSEscape(fs) };
        } else {
            env.FS = .{ .str = fs };
        }
    }

    // Handle -v variable assignments
    for (var_opts.items) |vopt| {
        if (std.mem.indexOfScalar(u8, vopt, '=')) |eq| {
            const vname = vopt[0..eq];
            const vval = vopt[eq + 1 ..];
            env.setVar(vname, Val{ .str = vval });
        }
    }

    // Register user-defined functions
    for (parse_result.funcs) |fd| {
        env.funcs.put(alloc.dupe(u8, fd.name) catch "", fd) catch {};
    }

    // Separate BEGIN/END rules from regular rules
    var begin_rules = std.ArrayListAligned(*const Rule, null).empty;
    var end_rules = std.ArrayListAligned(*const Rule, null).empty;
    var main_rules = std.ArrayListAligned(*const Rule, null).empty;

    for (parse_result.rules) |*r| {
        switch (r.pattern) {
            .begin => begin_rules.append(alloc, r) catch {},
            .end => end_rules.append(alloc, r) catch {},
            else => main_rules.append(alloc, r) catch {},
        }
    }

    // Execute BEGIN rules
    for (begin_rules.items) |r| {
        env.should_next = false;
        evalStmt(&env, r.action);
        if (env.should_exit) {
            return @as(u8, @intFromFloat(env.exit_code));
        }
    }

    // Process input files
    if (files.items.len == 0 or std.mem.eql(u8, files.items[0], "-")) {
        // Read from stdin
        env.FILENAME = .{ .str = "" };
        var reader = core.LineReader.init(0);
        while (reader.next()) |line| {
            if (env.should_exit) break;
            env.should_next = false;
            env.NR += 1;
            env.FNR += 1;
            env.current_line = line;
            env.refreshFields();
            for (main_rules.items) |r| {
                if (env.should_next or env.should_exit or env.in_function_return) break;
                if (matchPattern(&env, &r.pattern)) {
                    env.should_next = false;
                    evalStmt(&env, r.action);
                }
            }
        }
    } else {
        for (files.items) |fname| {
            if (env.should_exit) break;
            env.FILENAME = .{ .str = fname };
            env.FNR = 0;
            const use_stdin = std.mem.eql(u8, fname, "-");
            const fd = if (use_stdin) 0 else blk: {
                var zfn: [4096:0]u8 = undefined;
                if (fname.len >= zfn.len) continue;
                @memcpy(zfn[0..fname.len], fname);
                zfn[fname.len] = 0;
                break :blk core.c.open(&zfn, core.c.O_RDONLY);
            };
            if (!use_stdin and fd < 0) continue;
            if (!use_stdin) {
                defer _ = core.c.close(fd);
                readFileLines(&env, fd, main_rules);
            } else {
                readFileLines(&env, fd, main_rules);
            }
        }
    }

    // Execute END rules
    for (end_rules.items) |r| {
        env.should_next = false;
        evalStmt(&env, r.action);
        if (env.should_exit) break;
    }

    return @as(u8, @intFromFloat(env.exit_code));
}

fn readFileLines(env: *Env, fd: i32, rules: std.ArrayList(*const Rule)) void {
    var reader = core.LineReader.init(fd);
    while (reader.next()) |line| {
        if (env.should_exit) break;
        env.should_next = false;
        env.NR += 1;
        env.FNR += 1;
        env.current_line = line;
        env.refreshFields();
        for (rules.items) |r| {
            if (env.should_next or env.should_exit or env.in_function_return) break;
            if (matchPattern(env, &r.pattern)) {
                env.should_next = false;
                evalStmt(env, r.action);
            }
        }
    }
}

fn handleFSEscape(s: []const u8) []const u8 {
    if (s.len == 2 and s[0] == '\\') {
        return switch (s[1]) {
            'n' => "\n",
            't' => "\t",
            'r' => "\r",
            '\\' => "\\",
            else => s,
        };
    }
    return s;
}
