const std = @import("std");
const var_store = @import("var.zig");

const c = @import("cimport.zig").c;

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

/// Try to expand brace patterns. Returns null if no braces found.
pub fn expandBrace(allocator: std.mem.Allocator, raw: []const u8) !?WordList {
    if (std.mem.indexOfScalar(u8, raw, '{') == null) return null;
    const list = try expandBraceString(allocator, raw);
    if (list.words.len == 1 and std.mem.eql(u8, list.words[0], raw)) {
        list.deinit();
        return null;
    }
    return list;
}

fn expandBraceString(allocator: std.mem.Allocator, str: []const u8) !WordList {
    var i: usize = 0;
    while (i < str.len) {
        switch (str[i]) {
            '\\' => {
                i += 2;
            },
            '\'' => {
                i += 1;
                while (i < str.len and str[i] != '\'') : (i += 1) {}
                if (i < str.len) i += 1;
            },
            '"' => {
                i += 1;
                while (i < str.len and str[i] != '"') {
                    if (str[i] == '\\' and i + 1 < str.len) i += 2 else i += 1;
                }
                if (i < str.len) i += 1;
            },
            '$' => {
                if (i + 1 < str.len and str[i + 1] == '\'') {
                    i += 2;
                    while (i < str.len and str[i] != '\'') {
                        if (str[i] == '\\' and i + 1 < str.len) i += 2 else i += 1;
                    }
                    if (i < str.len) i += 1;
                } else if (i + 1 < str.len and str[i + 1] == '{') {
                    if (findMatchingBrace(str, i + 1)) |close| {
                        i = close + 1;
                    } else {
                        i += 1;
                    }
                } else if (i + 1 < str.len and str[i + 1] == '(') {
                    var paren_depth: usize = 1;
                    var j = i + 2;
                    while (j < str.len and paren_depth > 0) : (j += 1) {
                        if (str[j] == '(') paren_depth += 1;
                        if (str[j] == ')') paren_depth -= 1;
                    }
                    i = j;
                } else {
                    i += 1;
                }
            },
            '{' => {
                if (findMatchingBrace(str, i)) |close| {
                    const content = str[i + 1 .. close];
                    const parts = try parseBraceParts(allocator, content);
                    defer {
                        for (parts) |p| allocator.free(p);
                        allocator.free(parts);
                    }
                    if (parts.len > 1 or isRangeContent(content)) {
                        const prefix = str[0..i];
                        const suffix = if (close + 1 < str.len) str[close + 1 ..] else "";
                        var result = std.ArrayListAligned([]const u8, null).empty;
                        const expanded_suffix = try expandBraceString(allocator, suffix);
                        defer expanded_suffix.deinit();
                        for (parts) |part| {
                            for (expanded_suffix.words) |suf| {
                                const combined = try std.mem.concat(allocator, u8, &.{ prefix, part, suf });
                                try result.append(allocator, combined);
                            }
                        }
                        return WordList{ .words = try result.toOwnedSlice(allocator), .allocator = allocator };
                    }
                }
                i += 1;
            },
            else => {
                i += 1;
            },
        }
    }
    var words: std.ArrayListAligned([]const u8, null) = .empty;
    try words.append(allocator, try allocator.dupe(u8, str));
    return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
}

fn findMatchingBrace(str: []const u8, start: usize) ?usize {
    if (start >= str.len or str[start] != '{') return null;
    var depth: usize = 1;
    var i = start + 1;
    while (i < str.len and depth > 0) {
        switch (str[i]) {
            '\\' => {
                i += 2;
            },
            '\'' => {
                i += 1;
                while (i < str.len and str[i] != '\'') : (i += 1) {}
                if (i < str.len) i += 1;
            },
            '"' => {
                i += 1;
                while (i < str.len and str[i] != '"') {
                    if (str[i] == '\\' and i + 1 < str.len) i += 2 else i += 1;
                }
                if (i < str.len) i += 1;
            },
            '$' => {
                if (i + 1 < str.len and str[i + 1] == '\'') {
                    i += 2;
                    while (i < str.len and str[i] != '\'') {
                        if (str[i] == '\\' and i + 1 < str.len) i += 2 else i += 1;
                    }
                    if (i < str.len) i += 1;
                } else if (i + 1 < str.len and str[i + 1] == '{') {
                    if (findMatchingBrace(str, i + 1)) |close| {
                        i = close + 1;
                    } else {
                        i += 1;
                    }
                } else {
                    i += 1;
                }
            },
            '{' => {
                depth += 1;
                i += 1;
            },
            '}' => {
                depth -= 1;
                if (depth == 0) return i;
                i += 1;
            },
            else => {
                i += 1;
            },
        }
    }
    return null;
}

fn hasTopLevelComma(content: []const u8) bool {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < content.len) {
        switch (content[i]) {
            '\\' => {
                i += 2;
            },
            '\'' => {
                i += 1;
                while (i < content.len and content[i] != '\'') : (i += 1) {}
                if (i < content.len) i += 1;
            },
            '"' => {
                i += 1;
                while (i < content.len and content[i] != '"') {
                    if (content[i] == '\\' and i + 1 < content.len) i += 2 else i += 1;
                }
                if (i < content.len) i += 1;
            },
            '$' => {
                if (i + 1 < content.len and content[i + 1] == '\'') {
                    i += 2;
                    while (i < content.len and content[i] != '\'') {
                        if (content[i] == '\\' and i + 1 < content.len) i += 2 else i += 1;
                    }
                    if (i < content.len) i += 1;
                } else {
                    i += 1;
                }
            },
            '{' => {
                depth += 1;
                i += 1;
            },
            '}' => {
                if (depth > 0) depth -= 1;
                i += 1;
            },
            ',' => {
                if (depth == 0) return true;
                i += 1;
            },
            else => {
                i += 1;
            },
        }
    }
    return false;
}

fn expandPartAndAppend(allocator: std.mem.Allocator, parts: *std.ArrayListAligned([]const u8, null), part: []const u8) WordExpError!void {
    if (isRangeContent(part)) {
        const expanded = try expandRange(allocator, part);
        defer {
            for (expanded) |w| allocator.free(w);
            allocator.free(expanded);
        }
        for (expanded) |w| {
            try parts.append(allocator, try allocator.dupe(u8, w));
        }
    } else if (hasTopLevelComma(part)) {
        const sub_parts = try splitAndExpand(allocator, part);
        defer {
            for (sub_parts) |p| allocator.free(p);
            allocator.free(sub_parts);
        }
        for (sub_parts) |w| {
            try parts.append(allocator, try allocator.dupe(u8, w));
        }
    } else if (std.mem.indexOfScalar(u8, part, '{') != null) {
        const expanded = try expandBraceString(allocator, part);
        defer expanded.deinit();
        for (expanded.words) |w| {
            try parts.append(allocator, try allocator.dupe(u8, w));
        }
    } else {
        try parts.append(allocator, try allocator.dupe(u8, part));
    }
}

fn splitAndExpand(allocator: std.mem.Allocator, content: []const u8) WordExpError![][]const u8 {
    var parts = std.ArrayListAligned([]const u8, null).empty;
    var depth: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < content.len) {
        switch (content[i]) {
            '\\' => {
                i += 2;
            },
            '\'' => {
                i += 1;
                while (i < content.len and content[i] != '\'') : (i += 1) {}
                if (i < content.len) i += 1;
            },
            '"' => {
                i += 1;
                while (i < content.len and content[i] != '"') {
                    if (content[i] == '\\' and i + 1 < content.len) i += 2 else i += 1;
                }
                if (i < content.len) i += 1;
            },
            '$' => {
                if (i + 1 < content.len and content[i + 1] == '\'') {
                    i += 2;
                    while (i < content.len and content[i] != '\'') {
                        if (content[i] == '\\' and i + 1 < content.len) i += 2 else i += 1;
                    }
                    if (i < content.len) i += 1;
                } else {
                    i += 1;
                }
            },
            '{' => {
                depth += 1;
                i += 1;
            },
            '}' => {
                if (depth > 0) depth -= 1;
                i += 1;
            },
            ',' => {
                if (depth == 0) {
                    try expandPartAndAppend(allocator, &parts, content[start..i]);
                    start = i + 1;
                }
                i += 1;
            },
            else => {
                i += 1;
            },
        }
    }
    if (start <= content.len) {
        try expandPartAndAppend(allocator, &parts, content[start..]);
    }
    return parts.toOwnedSlice(allocator);
}

fn isNumeric(s: []const u8) bool {
    if (s.len == 0) return false;
    if (s.len > 1 and s[0] == '0') return false;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn isAlpha(s: []const u8) bool {
    if (s.len != 1) return false;
    const ch = s[0];
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn isRangeContent(content: []const u8) bool {
    const first_dd = std.mem.indexOf(u8, content, "..") orelse return false;
    const start_str = content[0..first_dd];
    const remaining = content[first_dd + 2 ..];
    if (start_str.len == 0 or remaining.len == 0) return false;
    const second_dd = std.mem.indexOf(u8, remaining, "..");
    const end_str = if (second_dd) |s| remaining[0..s] else remaining;
    const step_str = if (second_dd) |s| remaining[s + 2 ..] else "";
    if (end_str.len == 0) return false;
    if (step_str.len > 0 and !isNumeric(step_str)) return false;
    const start_num = isNumeric(start_str);
    const end_num = isNumeric(end_str);
    if (start_num and end_num) return true;
    const start_alpha = isAlpha(start_str);
    const end_alpha = isAlpha(end_str);
    if (start_alpha and end_alpha) return true;
    return false;
}

fn expandRange(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
    const first_dd = std.mem.indexOf(u8, content, "..").?;
    const start_str = content[0..first_dd];
    const remaining = content[first_dd + 2 ..];
    const second_dd = std.mem.indexOf(u8, remaining, "..");
    const end_str = if (second_dd) |s| remaining[0..s] else remaining;
    const step_str = if (second_dd) |s| remaining[s + 2 ..] else "";
    const step: i64 = if (step_str.len > 0) std.fmt.parseInt(i64, step_str, 10) catch 1 else 1;
    var result = std.ArrayListAligned([]const u8, null).empty;
    if (isNumeric(start_str)) {
        const start = std.fmt.parseInt(i64, start_str, 10) catch return error.Syntax;
        const end = std.fmt.parseInt(i64, end_str, 10) catch return error.Syntax;
        if (start <= end) {
            var val = start;
            while (val <= end) {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                try result.append(allocator, s);
                val += step;
            }
        } else {
            var val = start;
            while (val >= end) {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                try result.append(allocator, s);
                val -= step;
            }
        }
    } else {
        const start: i64 = @intCast(start_str[0]);
        const end: i64 = @intCast(end_str[0]);
        if (start <= end) {
            var val = start;
            while (val <= end) {
                const ch: u8 = @intCast(val);
                const s = try allocator.dupe(u8, &.{ch});
                try result.append(allocator, s);
                val += step;
            }
        } else {
            var val = start;
            while (val >= end) {
                const ch: u8 = @intCast(val);
                const s = try allocator.dupe(u8, &.{ch});
                try result.append(allocator, s);
                val -= step;
            }
        }
    }
    return result.toOwnedSlice(allocator);
}

fn parseBraceParts(allocator: std.mem.Allocator, content: []const u8) WordExpError![][]const u8 {
    if (isRangeContent(content)) {
        return expandRange(allocator, content);
    }
    if (hasTopLevelComma(content)) {
        return splitAndExpand(allocator, content);
    }
    var result: [][]const u8 = try allocator.alloc([]const u8, 1);
    result[0] = try allocator.dupe(u8, content);
    return result;
}

pub fn expandToken(allocator: std.mem.Allocator, raw: []const u8) WordExpError!WordList {
    const cleaned = try stripLineContinuation(allocator, raw);
    defer allocator.free(cleaned);

    if (try expandBrace(allocator, cleaned)) |result| {
        return result;
    }

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
    const expanded_params = try expandParamExpansion(allocator, substituted);
    defer allocator.free(expanded_params);
    const raw_z = try allocator.dupeZ(u8, expanded_params);
    defer allocator.free(raw_z);
    const flags: c_int = if (var_store.nounset) c.WRDE_UNDEF else 0;
    return expandRaw(allocator, raw_z, flags);
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
fn isFirstParamChar(ch: u8) bool {
    const r = switch (ch) {
        '?', '!', '-', '$', '@', '*', '#', '0' => true,
        '1'...'9' => true,
        else => std.ascii.isAlphabetic(ch) or ch == '_',
    };
    return r;
}

fn skipParamName(s: []const u8, pos: usize) usize {
    if (pos >= s.len) return pos;
    switch (s[pos]) {
        '?', '!', '-', '$', '@', '*', '#', '0' => return pos + 1,
        '1'...'9' => return pos + 1,
        else => {
            if (std.ascii.isAlphabetic(s[pos]) or s[pos] == '_') {
                var i = pos + 1;
                while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) : (i += 1) {}
                return i;
            }
            return pos;
        },
    }
}

fn writeStderr(msg: []const u8) void {
    _ = c.write(2, msg.ptr, @as(usize, msg.len));
}

fn getSimpleVarValue(name: []const u8) ?[]const u8 {
    if (name.len == 1) {
        switch (name[0]) {
            '?', '!', '$', '@', '*', '#', '-', '0' => return var_store.getSpecial(name[0]),
            '1'...'9' => return var_store.getPositionalValue(name[0] - '1'),
            else => {},
        }
    }
    if (var_store.get(name)) |v| return v.value;
    return null;
}

fn expandParamExpansion(allocator: std.mem.Allocator, raw: []const u8) WordExpError![]u8 {
    var result = std.ArrayListAligned(u8, null).empty;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            try result.append(allocator, raw[i]);
            try result.append(allocator, raw[i + 1]);
            i += 2;
            continue;
        }
        if (raw[i] == '$' and i + 1 < raw.len and raw[i + 1] == '{') {
            var depth: usize = 1;
            var j = i + 2;
            while (j < raw.len and depth > 0) : (j += 1) {
                if (raw[j] == '{') depth += 1;
                if (raw[j] == '}') depth -= 1;
            }
            if (depth == 0) {
                const close = j - 1;
                const inner = raw[i + 2 .. close];
                const expanded = try handleParamInner(allocator, inner);
                try result.appendSlice(allocator, expanded);
                allocator.free(expanded);
                i = close + 1;
            } else {
                try result.append(allocator, raw[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, raw[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

fn handleParamInner(allocator: std.mem.Allocator, content: []const u8) WordExpError![]u8 {
    if (content.len == 0) return error.Syntax;

    var pos: usize = 0;

    var bang = false;
    if (content[pos] == '!') {
        bang = true;
        pos += 1;
    }

    if (bang) {
        if (pos < content.len) {
            const prefix_start = pos;
            var prefix_end = prefix_start;
            while (prefix_end < content.len and content[prefix_end] != '*' and content[prefix_end] != '@') : (prefix_end += 1) {}
            if (prefix_end < content.len and (content[prefix_end] == '*' or content[prefix_end] == '@')) {
                const prefix = content[prefix_start..prefix_end];
                return handleMatchingPrefix(allocator, prefix);
            }
            if (isFirstParamChar(content[pos])) {
                const name = content[pos..];
                return handleSimpleIndirect(allocator, name);
            }
        }
        return error.Syntax;
    }

    var hash = false;
    if (pos < content.len and content[pos] == '#') {
        if (pos + 1 < content.len and isFirstParamChar(content[pos + 1])) {
            hash = true;
            pos += 1;
        }
    }

    const name_start = pos;
    pos = skipParamName(content, pos);
    if (pos == name_start) return error.Syntax;
    const name = content[name_start..pos];

    if (hash) {
        const val = getSimpleVarValue(name) orelse "";
        var buf: [32]u8 = undefined;
        const len_str = std.fmt.bufPrint(&buf, "{d}", .{val.len}) catch "0";
        return allocator.dupe(u8, len_str);
    }

    if (pos >= content.len) {
        if (var_store.get(name)) |v| {
            return allocator.dupe(u8, v.value);
        }
        if (name.len == 1) {
            switch (name[0]) {
                '?', '!', '-', '$', '@', '*', '#', '0' => {
                    const val = var_store.getSpecial(name[0]);
                    return allocator.dupe(u8, val);
                },
                '1'...'9' => {
                    const val = var_store.getPositionalValue(name[0] - '1');
                    return allocator.dupe(u8, val);
                },
                else => {},
            }
        }
        if (var_store.nounset) {
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "bash: line 1: {s}: unbound variable\n", .{name}) catch "bash: unbound variable\n";
            writeStderr(msg);
            return error.UndefinedVar;
        }
        return allocator.dupe(u8, "");
    }

    if (content[pos] == ':') {
        pos += 1;
        if (pos >= content.len) {
            if (var_store.get(name)) |v| return allocator.dupe(u8, v.value);
            return allocator.dupe(u8, "");
        }
        switch (content[pos]) {
            '-', '=', '?', '+' => {
                const op = content[pos];
                pos += 1;
                const word = content[pos..];
                return handleOpWithColon(allocator, name, op, word, true);
            },
            else => {
                const substr_spec = content[pos..];
                return handleSubstring(allocator, name, substr_spec);
            },
        }
    }

    switch (content[pos]) {
        '-' => {
            pos += 1;
            return handleOpWithColon(allocator, name, '-', content[pos..], false);
        },
        '=' => {
            pos += 1;
            return handleOpWithColon(allocator, name, '=', content[pos..], false);
        },
        '?' => {
            pos += 1;
            return handleOpWithColon(allocator, name, '?', content[pos..], false);
        },
        '+' => {
            pos += 1;
            return handleOpWithColon(allocator, name, '+', content[pos..], false);
        },
        '/' => {
            pos += 1;
            var global = false;
            if (pos < content.len and content[pos] == '/') {
                global = true;
                pos += 1;
            }
            const rest = content[pos..];
            return handlePatternReplace(allocator, name, rest, global);
        },
        '#' => {
            pos += 1;
            var long = false;
            if (pos < content.len and content[pos] == '#') {
                long = true;
                pos += 1;
            }
            const pattern = content[pos..];
            return handlePrefixRemove(allocator, name, pattern, long);
        },
        '%' => {
            pos += 1;
            var long = false;
            if (pos < content.len and content[pos] == '%') {
                long = true;
                pos += 1;
            }
            const pattern = content[pos..];
            return handleSuffixRemove(allocator, name, pattern, long);
        },
        else => return error.Syntax,
    }
}

fn handleOpWithColon(allocator: std.mem.Allocator, name: []const u8, op: u8, word: []const u8, colon: bool) WordExpError![]u8 {
    const val = var_store.get(name);

    switch (op) {
        '-' => {
            var use_default = false;
            if (val == null) {
                use_default = true;
            } else if (colon and val.?.value.len == 0) {
                use_default = true;
            }
            if (use_default) {
                const expanded = try expandParamExpansion(allocator, word);
                return expanded;
            }
            return allocator.dupe(u8, val.?.value);
        },
        '=' => {
            var use_default = false;
            if (val == null) {
                use_default = true;
            } else if (colon and val.?.value.len == 0) {
                use_default = true;
            }
            if (use_default) {
                const expanded = try expandParamExpansion(allocator, word);
                _ = var_store.set(name, expanded, false);
                return expanded;
            }
            return allocator.dupe(u8, val.?.value);
        },
        '?' => {
            var is_error = false;
            if (val == null) {
                is_error = true;
            } else if (colon and val.?.value.len == 0) {
                is_error = true;
            }
            if (is_error) {
                var msg_buf: [4096]u8 = undefined;
                const msg = if (word.len > 0)
                    std.fmt.bufPrint(&msg_buf, "bash: {s}: {s}\n", .{ name, word }) catch "bash: parameter error\n"
                else
                    std.fmt.bufPrint(&msg_buf, "bash: {s}: parameter null or not set\n", .{name}) catch "bash: parameter error\n";
                writeStderr(msg);
                return error.UndefinedVar;
            }
            return allocator.dupe(u8, val.?.value);
        },
        '+' => {
            var show_alt = false;
            if (val != null) {
                if (!colon) {
                    show_alt = true;
                } else if (val.?.value.len > 0) {
                    show_alt = true;
                }
            }
            if (show_alt) {
                const expanded = try expandParamExpansion(allocator, word);
                return expanded;
            }
            return allocator.dupe(u8, "");
        },
        else => unreachable,
    }
}

fn handleSubstring(allocator: std.mem.Allocator, name: []const u8, spec: []const u8) ![]u8 {
    if (var_store.get(name)) |v| {
        const val = v.value;
        if (val.len == 0) return allocator.dupe(u8, "");

        const trimmed = std.mem.trim(u8, spec, " ");
        if (trimmed.len == 0) return allocator.dupe(u8, val);

        var offset_str: []const u8 = trimmed;
        var length_str: ?[]const u8 = null;

        if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon_pos| {
            offset_str = trimmed[0..colon_pos];
            length_str = trimmed[colon_pos + 1 ..];
        }

        const offset = std.fmt.parseInt(i64, std.mem.trim(u8, offset_str, " "), 10) catch 0;
        const length = if (length_str) |ls|
            std.fmt.parseInt(i64, std.mem.trim(u8, ls, " "), 10) catch null
        else
            null;

        const val_len = @as(i64, @intCast(val.len));
        var start: i64 = if (offset >= 0) offset else val_len + offset;
        if (start < 0) start = 0;

        if (start >= val_len) return allocator.dupe(u8, "");

        var end: i64 = val_len;
        if (length) |len| {
            if (len >= 0) {
                end = start + len;
            } else {
                end = start;
            }
        }
        if (end > val_len) end = val_len;
        if (end <= start) return allocator.dupe(u8, "");

        return allocator.dupe(u8, val[@as(usize, @intCast(start))..@as(usize, @intCast(end))]);
    }
    return allocator.dupe(u8, "");
}

fn handlePatternReplace(allocator: std.mem.Allocator, name: []const u8, rest: []const u8, global: bool) ![]u8 {
    if (var_store.get(name)) |v| {
        const val = v.value;

        var slash_pos: ?usize = null;
        for (rest, 0..) |ch, j| {
            if (ch == '/') {
                slash_pos = j;
                break;
            }
        }

        const pattern = if (slash_pos) |sp| rest[0..sp] else rest;
        const replacement = if (slash_pos) |sp| rest[sp + 1 ..] else "";

        if (pattern.len == 0) return allocator.dupe(u8, val);

        var result = std.ArrayListAligned(u8, null).empty;
        var ii: usize = 0;
        var did_replace = false;

        while (ii < val.len) {
            if ((!global and !did_replace) or global) {
                if (std.mem.indexOf(u8, val[ii..], pattern)) |pos| if (pos == 0) {
                    try result.appendSlice(allocator, replacement);
                    ii += pattern.len;
                    did_replace = true;
                    if (!global) {
                        try result.appendSlice(allocator, val[ii..]);
                        return result.toOwnedSlice(allocator);
                    }
                    continue;
                };
            }
            try result.append(allocator, val[ii]);
            ii += 1;
        }
        return result.toOwnedSlice(allocator);
    }
    return allocator.dupe(u8, "");
}

fn handlePrefixRemove(allocator: std.mem.Allocator, name: []const u8, pattern: []const u8, _: bool) ![]u8 {
    if (var_store.get(name)) |v| {
        const val = v.value;
        if (val.len == 0 or pattern.len == 0) return allocator.dupe(u8, val);
        if (std.mem.startsWith(u8, val, pattern)) {
            return allocator.dupe(u8, val[pattern.len..]);
        }
        return allocator.dupe(u8, val);
    }
    return allocator.dupe(u8, "");
}

fn handleSuffixRemove(allocator: std.mem.Allocator, name: []const u8, pattern: []const u8, _: bool) ![]u8 {
    if (var_store.get(name)) |v| {
        const val = v.value;
        if (val.len == 0 or pattern.len == 0) return allocator.dupe(u8, val);
        if (std.mem.endsWith(u8, val, pattern)) {
            return allocator.dupe(u8, val[0 .. val.len - pattern.len]);
        }
        return allocator.dupe(u8, val);
    }
    return allocator.dupe(u8, "");
}

fn handleSimpleIndirect(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (name.len == 0) return allocator.dupe(u8, "");
    if (var_store.get(name)) |v| {
        if (v.value.len == 0) return allocator.dupe(u8, "");
        if (var_store.get(v.value)) |v2| {
            return allocator.dupe(u8, v2.value);
        }
        return allocator.dupe(u8, "");
    }
    return allocator.dupe(u8, "");
}

fn handleMatchingPrefix(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    const all_vars = var_store.allVars();
    var matching = std.ArrayListAligned(u8, null).empty;

    for (all_vars) |v| {
        if (std.mem.startsWith(u8, v.name, prefix)) {
            if (matching.items.len > 0) try matching.append(allocator, ' ');
            try matching.appendSlice(allocator, v.name);
        }
    }

    return matching.toOwnedSlice(allocator);
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
                // Check for hex prefix 0x or 0X
                if (ch == '0' and self.pos + 1 < self.expr.len and (self.expr[self.pos + 1] == 'x' or self.expr[self.pos + 1] == 'X')) {
                    self.pos += 2;
                    while (self.pos < self.expr.len) {
                        const hexch = self.expr[self.pos];
                        if ((hexch >= '0' and hexch <= '9') or (hexch >= 'a' and hexch <= 'f') or (hexch >= 'A' and hexch <= 'F')) {
                            self.pos += 1;
                        } else {
                            break;
                        }
                    }
                    return std.fmt.parseInt(i64, self.expr[start..self.pos], 0) catch return error.Syntax;
                }
                // Check for octal prefix 0
                if (ch == '0') {
                    self.pos += 1;
                    while (self.pos < self.expr.len and self.expr[self.pos] >= '0' and self.expr[self.pos] <= '7') {
                        self.pos += 1;
                    }
                    return std.fmt.parseInt(i64, self.expr[start..self.pos], 0) catch return error.Syntax;
                }
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
