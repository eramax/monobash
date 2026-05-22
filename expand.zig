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

    pub fn deinit(self: *WordList) void {
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

    // Check if the entire token is a $'...' ANSI-C quoted string
    if (isPureAnsiC(cleaned)) {
        const expanded = try parseAnsiCString(allocator, cleaned);
        var words: std.ArrayListAligned([]const u8, null) = .empty;
        try words.append(allocator, expanded);
        return WordList{ .words = try words.toOwnedSlice(allocator), .allocator = allocator };
    }

    // For mixed or non-ANSI-C tokens, handle variable expansion and wordpexp
    const with_ansi = try expandAnsiC(allocator, cleaned);
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
    // For non-pure ANSI-C, we embed the expanded content (but wordpexp may reject newlines etc.)
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
            const content = raw[start..end];
            try result.appendSlice(allocator, content);
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
