const std = @import("std");
const var_store = @import("var.zig");

const c = @cImport({
    @cInclude("wordexp.h");
});

pub const WordExpError = error{
    OutOfMemory,
    Syntax,
    UndefinedVar,
};

pub const WordList = struct {
    words: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const WordList) void {
        for (self.words) |w| self.allocator.free(w);
        self.allocator.free(self.words);
    }
};

fn expandRaw(allocator: std.mem.Allocator, raw_z: [:0]u8, flags: c_int) WordExpError!WordList {
    var we: c.wordexp_t = std.mem.zeroes(c.wordexp_t);
    const result = c.wordexp(raw_z.ptr, &we, flags);

    switch (result) {
        c.WRDE_NOSPACE => {
            c.wordfree(&we);
            return error.OutOfMemory;
        },
        c.WRDE_SYNTAX => return error.Syntax,
        c.WRDE_UNDEF => return error.UndefinedVar,
        else => {},
    }

    defer c.wordfree(&we);

    var words: std.ArrayListAligned([]const u8, null) = .empty;
    errdefer words.deinit(allocator);
    try words.ensureTotalCapacity(allocator, we.we_wordc);
    for (0..we.we_wordc) |i| {
        const s = we.we_wordv[i];
        words.appendAssumeCapacity(try allocator.dupe(u8, std.mem.sliceTo(s, 0)));
    }
    return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
}

pub fn expandToken(allocator: std.mem.Allocator, raw: []const u8) WordExpError!WordList {
    const cleaned = try stripLineContinuation(allocator, raw);
    defer allocator.free(cleaned);

    // Check if the entire token is a '...' single-quoted string
    if (cleaned.len >= 2 and cleaned[0] == '\'' and cleaned[cleaned.len - 1] == '\'') {
        const content = cleaned[1 .. cleaned.len - 1];
        var words: std.ArrayListAligned([]const u8, null) = .empty;
        try words.append(allocator, try allocator.dupe(u8, content));
        return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
    }

    // Check if the entire token is a $'...' ANSI-C quoted string
    if (isPureAnsiC(cleaned)) {
        const expanded = try parseAnsiCString(allocator, cleaned);
        var words: std.ArrayListAligned([]const u8, null) = .empty;
        try words.append(allocator, expanded);
        return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
    }

    // For mixed or non-ANSI-C tokens, handle variable expansion and wordpexp
    const with_arith = try preprocessArithmetic(allocator, cleaned);
    defer allocator.free(with_arith);

    const with_ansi = try expandAnsiC(allocator, with_arith);
    defer allocator.free(with_ansi);

    // Check if result still contains ANSI-C artifacts that wordpexp would reject
    // (e.g., embedded newlines from expansion — treat as single word)
    if (std.mem.indexOfScalar(u8, with_ansi, '\n') != null) {
        const expanded = try allocator.dupe(u8, with_ansi);
        var words: std.ArrayListAligned([]const u8, null) = .empty;
        try words.append(allocator, expanded);
        return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
    }

    const substituted = try expandPositional(allocator, with_ansi);
    defer allocator.free(substituted);
    const raw_z = try allocator.dupeZ(u8, substituted);
    defer allocator.free(raw_z);
    return expandRaw(allocator, raw_z, 0);
}

fn isPureAnsiC(raw: []const u8) bool {
    return raw.len >= 4 and raw[0] == '$' and raw[1] == '\'' and raw[raw.len - 1] == '\'';
}

fn parseAnsiCString(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const content = raw[2 .. raw.len - 1];
    var result = std.ArrayListAligned(u8, null).empty;
    var j: usize = 0;
    while (j < content.len) {
        if (content[j] == '\\' and j + 1 < content.len) {
            const next = content[j + 1];
            switch (next) {
                'n' => { try result.append(allocator, '\n'); j += 2; },
                't' => { try result.append(allocator, '\t'); j += 2; },
                'r' => { try result.append(allocator, '\r'); j += 2; },
                '\\' => { try result.append(allocator, '\\'); j += 2; },
                '\'' => { try result.append(allocator, '\''); j += 2; },
                '"' => { try result.append(allocator, '"'); j += 2; },
                'a' => { try result.append(allocator, '\x07'); j += 2; },
                'b' => { try result.append(allocator, '\x08'); j += 2; },
                'e' => { try result.append(allocator, '\x1B'); j += 2; },
                'f' => { try result.append(allocator, '\x0C'); j += 2; },
                'v' => { try result.append(allocator, '\x0B'); j += 2; },
                '0'...'7' => {
                    var octal_val: u8 = 0;
                    var digits: u8 = 0;
                    while (j + 1 < content.len and content[j + 1] >= '0' and content[j + 1] <= '7' and digits < 3) : (digits += 1) {
                        j += 1;
                        octal_val = octal_val * 8 + (content[j] - '0');
                    }
                    try result.append(allocator, octal_val);
                    j += 1;
                },
                'x' => {
                    j += 2;
                    var hex_val: u8 = 0;
                    var digits: u8 = 0;
                    while (j < content.len and digits < 2) : (digits += 1) {
                        const ch = content[j];
                        hex_val = hex_val * 16 + switch (ch) {
                            '0'...'9' => ch - '0',
                            'a'...'f' => ch - 'a' + 10,
                            'A'...'F' => ch - 'A' + 10,
                            else => break,
                        };
                        j += 1;
                    }
                    try result.append(allocator, hex_val);
                },
                'c' => {
                    if (j + 2 < content.len) {
                        const ctrl = content[j + 2];
                        try result.append(allocator, @as(u8, @intCast(ctrl & 0x1F)));
                        j += 3;
                    } else {
                        j += 2;
                    }
                },
                else => {
                    try result.append(allocator, '\\');
                    try result.append(allocator, next);
                    j += 2;
                },
            }
        } else {
            try result.append(allocator, content[j]);
            j += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

fn expandAnsiC(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Handle $'...' ANSI-C quoting embedded in non-pure tokens
    // Parse escape sequences inside the $'...' portion
    var result = std.ArrayListAligned(u8, null).empty;
    try result.ensureTotalCapacity(allocator, raw.len);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '$' and i + 2 < raw.len and raw[i + 1] == '\'') {
            const start = i + 2;
            const end = if (std.mem.indexOfScalar(u8, raw[start..], '\'')) |pos| start + pos else {
                result.appendAssumeCapacity(raw[i]);
                i += 1;
                continue;
            };
            const ansi_content = raw[start..end];
            // Parse escape sequences in the ANSI-C string content
            var j: usize = 0;
            while (j < ansi_content.len) {
                if (ansi_content[j] == '\\' and j + 1 < ansi_content.len) {
                    const next = ansi_content[j + 1];
                    switch (next) {
                        'n' => { try result.append(allocator, '\n'); j += 2; },
                        't' => { try result.append(allocator, '\t'); j += 2; },
                        'r' => { try result.append(allocator, '\r'); j += 2; },
                        '\\' => { try result.append(allocator, '\\'); j += 2; },
                        '\'' => { try result.append(allocator, '\''); j += 2; },
                        '"' => { try result.append(allocator, '"'); j += 2; },
                        'a' => { try result.append(allocator, '\x07'); j += 2; },
                        'b' => { try result.append(allocator, '\x08'); j += 2; },
                        'e' => { try result.append(allocator, '\x1B'); j += 2; },
                        'f' => { try result.append(allocator, '\x0C'); j += 2; },
                        'v' => { try result.append(allocator, '\x0B'); j += 2; },
                        '0'...'7' => {
                            var octal_val: u8 = 0;
                            var digits: u8 = 0;
                            while (j + 1 < ansi_content.len and ansi_content[j + 1] >= '0' and ansi_content[j + 1] <= '7' and digits < 3) : (digits += 1) {
                                j += 1;
                                octal_val = octal_val * 8 + (ansi_content[j] - '0');
                            }
                            try result.append(allocator, octal_val);
                            j += 1;
                        },
                        'x' => {
                            j += 2;
                            var hex_val: u8 = 0;
                            var digits: u8 = 0;
                            while (j < ansi_content.len and digits < 2) : (digits += 1) {
                                const ch = ansi_content[j];
                                hex_val = hex_val * 16 + switch (ch) {
                                    '0'...'9' => ch - '0',
                                    'a'...'f' => ch - 'a' + 10,
                                    'A'...'F' => ch - 'A' + 10,
                                    else => break,
                                };
                                j += 1;
                            }
                            try result.append(allocator, hex_val);
                        },
                        'c' => {
                            if (j + 2 < ansi_content.len) {
                                const ctrl = ansi_content[j + 2];
                                try result.append(allocator, @as(u8, @intCast(ctrl & 0x1F)));
                                j += 3;
                            } else {
                                j += 2;
                            }
                        },
                        else => {
                            try result.append(allocator, '\\');
                            try result.append(allocator, next);
                            j += 2;
                        },
                    }
                } else {
                    try result.append(allocator, ansi_content[j]);
                    j += 1;
                }
            }
            i = end + 1;
        } else {
            try result.append(allocator, raw[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

fn expandPositional(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Replace $N (where N is a digit) with positional parameter values
    // Also handle special vars that wordpexp doesn't handle ($?, $!)
    var result = std.ArrayListAligned(u8, null).empty;
    try result.ensureTotalCapacity(allocator, raw.len);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            result.appendAssumeCapacity(raw[i]);
            result.appendAssumeCapacity(raw[i + 1]);
            i += 2;
            continue;
        }
        if (raw[i] == '$' and i + 1 < raw.len) {
            // Special vars that wordpexp DOES handle: $$, $0, $- (pass through)
            // Special vars that wordpexp DOES NOT handle: $?, $!
            if (raw[i + 1] == '?' or raw[i + 1] == '!' or raw[i + 1] == '-') {
                const val = var_store.getSpecial(raw[i + 1]);
                try result.appendSlice(allocator, val);
                i += 2;
                continue;
            }
            if (raw[i + 1] >= '1' and raw[i + 1] <= '9') {
                const idx = raw[i + 1] - '1';
                const val = var_store.getPositionalValue(@intCast(idx));
                try result.appendSlice(allocator, val);
                i += 2;
                continue;
            }
            if (raw[i + 1] == '@' or raw[i + 1] == '*') {
                const val = var_store.getSpecial(raw[i + 1]);
                try result.appendSlice(allocator, val);
                i += 2;
                continue;
            }
            if (raw[i + 1] == '#') {
                const val = var_store.getSpecial('#');
                try result.appendSlice(allocator, val);
                i += 2;
                continue;
            }
        }
        result.appendAssumeCapacity(raw[i]);
        i += 1;
    }
    return result.toOwnedSlice(allocator);
}

pub fn expandTokenSafe(allocator: std.mem.Allocator, raw: []const u8) WordExpError!WordList {
    const cleaned = try stripLineContinuation(allocator, raw);
    defer allocator.free(cleaned);
    const raw_z = try allocator.dupeZ(u8, cleaned);
    defer allocator.free(raw_z);
    return expandRaw(allocator, raw_z, c.WRDE_UNDEF);
}

pub fn evalArithmeticFromStr(_: std.mem.Allocator, expr: []const u8) !i64 {
    var p = ArithParser{ .expr = expr, .pos = 0 };
    p.skipWhitespace();
    return p.parseExpr();
}

const ArithError = error{Syntax, DivisionByZero};

const ArithParser = struct {
    expr: []const u8,
    pos: usize,

    fn peek(self: ArithParser) ?u8 {
        if (self.pos >= self.expr.len) return null;
        return self.expr[self.pos];
    }

    fn next(self: *ArithParser) ?u8 {
        if (self.pos >= self.expr.len) return null;
        const ch = self.expr[self.pos];
        self.pos += 1;
        return ch;
    }

    fn skipWhitespace(self: *ArithParser) void {
        while (self.pos < self.expr.len and std.ascii.isWhitespace(self.expr[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseExpr(self: *ArithParser) ArithError!i64 {
        const left = try self.parseLogicalOr();

        self.skipWhitespace();
        if (self.peek() == '?') {
            _ = self.next();
            self.skipWhitespace();
            const true_val = try self.parseExpr();
            self.skipWhitespace();
            if (self.peek() != ':') return error.Syntax;
            _ = self.next();
            self.skipWhitespace();
            const false_val = try self.parseExpr();
            return if (left != 0) true_val else false_val;
        }

        return left;
    }

    fn parseLogicalOr(self: *ArithParser) ArithError!i64 {
        var left = try self.parseLogicalAnd();
        while (true) {
            self.skipWhitespace();
            if (self.pos + 1 < self.expr.len and self.expr[self.pos] == '|' and self.expr[self.pos + 1] == '|') {
                self.pos += 2;
                const right = try self.parseLogicalAnd();
                left = if (left != 0 or right != 0) 1 else 0;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseLogicalAnd(self: *ArithParser) ArithError!i64 {
        var left = try self.parseBitwiseOr();
        while (true) {
            self.skipWhitespace();
            if (self.pos + 1 < self.expr.len and self.expr[self.pos] == '&' and self.expr[self.pos + 1] == '&') {
                self.pos += 2;
                const right = try self.parseBitwiseOr();
                left = if (left != 0 and right != 0) 1 else 0;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseBitwiseOr(self: *ArithParser) ArithError!i64 {
        var left = try self.parseBitwiseXor();
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '|') {
                if (self.pos + 1 < self.expr.len and self.expr[self.pos + 1] == '|') break;
                _ = self.next();
                const right = try self.parseBitwiseXor();
                left = left | right;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseBitwiseXor(self: *ArithParser) ArithError!i64 {
        var left = try self.parseBitwiseAnd();
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '^') {
                _ = self.next();
                const right = try self.parseBitwiseAnd();
                left = left ^ right;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseBitwiseAnd(self: *ArithParser) ArithError!i64 {
        var left = try self.parseEquality();
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '&') {
                if (self.pos + 1 < self.expr.len and self.expr[self.pos + 1] == '&') break;
                _ = self.next();
                const right = try self.parseEquality();
                left = left & right;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseEquality(self: *ArithParser) ArithError!i64 {
        var left = try self.parseComparison();
        while (true) {
            self.skipWhitespace();
            if (self.pos + 1 < self.expr.len) {
                if (self.expr[self.pos] == '=' and self.expr[self.pos + 1] == '=') {
                    self.pos += 2;
                    const right = try self.parseComparison();
                    left = if (left == right) 1 else 0;
                } else if (self.expr[self.pos] == '!' and self.expr[self.pos + 1] == '=') {
                    self.pos += 2;
                    const right = try self.parseComparison();
                    left = if (left != right) 1 else 0;
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return left;
    }

    fn parseComparison(self: *ArithParser) ArithError!i64 {
        var left = try self.parseShift();
        while (true) {
            self.skipWhitespace();
            if (self.pos + 1 < self.expr.len) {
                if (self.expr[self.pos] == '<' and self.expr[self.pos + 1] == '=') {
                    self.pos += 2;
                    const right = try self.parseShift();
                    left = if (left <= right) 1 else 0;
                } else if (self.expr[self.pos] == '>' and self.expr[self.pos + 1] == '=') {
                    self.pos += 2;
                    const right = try self.parseShift();
                    left = if (left >= right) 1 else 0;
                } else if (self.expr[self.pos] == '<' and (self.pos + 1 >= self.expr.len or self.expr[self.pos + 1] != '<')) {
                    _ = self.next();
                    const right = try self.parseShift();
                    left = if (left < right) 1 else 0;
                } else if (self.expr[self.pos] == '>' and (self.pos + 1 >= self.expr.len or self.expr[self.pos + 1] != '>')) {
                    _ = self.next();
                    const right = try self.parseShift();
                    left = if (left > right) 1 else 0;
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return left;
    }

    fn parseShift(self: *ArithParser) ArithError!i64 {
        var left = try self.parseAdditive();
        while (true) {
            self.skipWhitespace();
            if (self.pos + 1 < self.expr.len) {
                if (self.expr[self.pos] == '<' and self.expr[self.pos + 1] == '<') {
                    self.pos += 2;
                    const right = try self.parseAdditive();
                    left = left << @as(u6, @intCast(right));
                } else if (self.expr[self.pos] == '>' and self.expr[self.pos + 1] == '>') {
                    self.pos += 2;
                    const right = try self.parseAdditive();
                    left = left >> @as(u6, @intCast(right));
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return left;
    }

    fn parseAdditive(self: *ArithParser) ArithError!i64 {
        var left = try self.parseMultiplicative();
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '+') {
                _ = self.next();
                const right = try self.parseMultiplicative();
                left = left + right;
            } else if (self.peek() == '-') {
                _ = self.next();
                const right = try self.parseMultiplicative();
                left = left - right;
            } else {
                break;
            }
        }
        return left;
    }

    fn parseMultiplicative(self: *ArithParser) ArithError!i64 {
        var left = try self.parseUnary();
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '*') {
                _ = self.next();
                const right = try self.parseUnary();
                left = left * right;
            } else if (self.peek() == '/') {
                _ = self.next();
                const right = try self.parseUnary();
                if (right == 0) return error.DivisionByZero;
                left = @divTrunc(left, right);
            } else if (self.peek() == '%') {
                _ = self.next();
                const right = try self.parseUnary();
                if (right == 0) return error.DivisionByZero;
                left = @rem(left, right);
            } else {
                break;
            }
        }
        return left;
    }

    fn parseUnary(self: *ArithParser) ArithError!i64 {
        self.skipWhitespace();
        if (self.peek()) |ch| {
            switch (ch) {
                '+' => {
                    _ = self.next();
                    return self.parseUnary();
                },
                '-' => {
                    _ = self.next();
                    return -try self.parseUnary();
                },
                '~' => {
                    _ = self.next();
                    return ~try self.parseUnary();
                },
                '!' => {
                    _ = self.next();
                    const val = try self.parseUnary();
                    return if (val == 0) 1 else 0;
                },
                else => return self.parsePrimary(),
            }
        }
        return error.Syntax;
    }

    fn parsePrimary(self: *ArithParser) ArithError!i64 {
        self.skipWhitespace();

        if (self.peek()) |ch| {
            if (ch == '(') {
                _ = self.next();
                const val = try self.parseExpr();
                self.skipWhitespace();
                if (self.peek() != ')') return error.Syntax;
                _ = self.next();
                return val;
            }

            if (ch >= '0' and ch <= '9') {
                const start = self.pos;
                while (self.pos < self.expr.len and self.expr[self.pos] >= '0' and self.expr[self.pos] <= '9') {
                    self.pos += 1;
                }
                return std.fmt.parseInt(i64, self.expr[start..self.pos], 10) catch return error.Syntax;
            }

            if (ch == '$') {
                _ = self.next();
                return self.parseVariableRef();
            }

            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start = self.pos;
                while (self.pos < self.expr.len) {
                    const cur = self.expr[self.pos];
                    if (std.ascii.isAlphanumeric(cur) or cur == '_') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                const name = self.expr[start..self.pos];
                return self.getVarValue(name);
            }
        }

        return error.Syntax;
    }

    fn parseVariableRef(self: *ArithParser) ArithError!i64 {
        if (self.peek()) |ch| {
            if (ch == '{') {
                _ = self.next();
                const start = self.pos;
                while (self.pos < self.expr.len) {
                    if (self.expr[self.pos] == '}') {
                        const name = self.expr[start..self.pos];
                        _ = self.next();
                        return self.getVarValue(name);
                    }
                    self.pos += 1;
                }
                return error.Syntax;
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start = self.pos;
                while (self.pos < self.expr.len) {
                    const cur = self.expr[self.pos];
                    if (std.ascii.isAlphanumeric(cur) or cur == '_') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                const name = self.expr[start..self.pos];
                return self.getVarValue(name);
            }
        }
        return error.Syntax;
    }

    fn getVarValue(self: *ArithParser, name: []const u8) i64 {
        _ = self;
        if (var_store.get(name)) |v| {
            return std.fmt.parseInt(i64, v.value, 10) catch 0;
        }
        return 0;
    }
};

fn preprocessArithmetic(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var result = std.ArrayListAligned(u8, null).empty;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '$' and i + 2 < raw.len and raw[i + 1] == '(' and raw[i + 2] == '(') {
            var depth: usize = 2;
            const start = i + 3;
            var j = start;
            while (j < raw.len) {
                if (raw[j] == '(') {
                    depth += 1;
                } else if (raw[j] == ')') {
                    depth -= 1;
                    if (depth == 0) {
                        const expr = raw[start..j - 1];
                        const val = evalArithmeticFromStr(allocator, expr) catch {
                            try result.appendSlice(allocator, raw[i..]);
                            i = raw.len;
                            break;
                        };
                        var buf: [32]u8 = undefined;
                        const val_str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch "0";
                        try result.appendSlice(allocator, val_str);
                        i = j + 1;
                        break;
                    }
                }
                j += 1;
            }
            if (j >= raw.len and depth > 0) {
                try result.appendSlice(allocator, raw[i..]);
                break;
            }
        } else {
            try result.append(allocator, raw[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

fn stripLineContinuation(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Find backslash-newline sequences and remove them
    var result = std.ArrayListAligned(u8, null).empty;
    try result.ensureTotalCapacity(allocator, raw.len);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len and raw[i + 1] == '\n') {
            i += 2;
        } else {
            result.appendAssumeCapacity(raw[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}
