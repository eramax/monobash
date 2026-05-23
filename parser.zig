const std = @import("std");
const c = @import("cimport.zig").c;

const maxU32 = std.math.maxInt(u32);

pub const NodeType = struct {
    id: u32,
    tree: ?*const TreeType,

    pub fn isNull(self: NodeType) bool {
        return self.tree == null or self.id == maxU32;
    }

    pub fn @"null"() NodeType {
        return .{ .id = maxU32, .tree = null };
    }
};

pub const TreeType = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListAligned(NodeData, null),
    source: [:0]const u8,

    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8) *TreeType {
        const self = allocator.create(TreeType) catch @panic("OOM");
        self.* = .{
            .allocator = allocator,
            .nodes = std.ArrayListAligned(NodeData, null).empty,
            .source = source,
        };
        return self;
    }

    pub fn deinit(self: *TreeType) void {
        const alloc = self.allocator;
        for (self.nodes.items) |*nd| {
            alloc.free(nd.name);
            if (nd.field_name) |fn_| alloc.free(fn_);
        }
        self.nodes.deinit(alloc);
        alloc.destroy(self);
    }

    fn addNode(self: *TreeType, name: []const u8, start: u32, end: u32, named: bool, field_name: ?[]const u8) u32 {
        const alloc = self.allocator;
        const name_dup = alloc.dupe(u8, name) catch @panic("OOM");
        const fname_dup = if (field_name) |fn_| alloc.dupe(u8, fn_) catch @panic("OOM") else null;
        const data = NodeData{
            .name = name_dup,
            .start_byte = start,
            .end_byte = end,
            .first_child = maxU32,
            .next_sibling = maxU32,
            .parent = maxU32,
            .named = named,
            .field_name = fname_dup,
        };
        const id = @as(u32, @intCast(self.nodes.items.len));
        self.nodes.append(alloc, data) catch @panic("OOM");
        return id;
    }

    fn setChildLink(self: *TreeType, parent_id: u32, child_id: u32) void {
        const parent = &self.nodes.items[parent_id];
        if (parent.first_child == maxU32) {
            parent.first_child = child_id;
        } else {
            var last = parent.first_child;
            while (self.nodes.items[last].next_sibling != maxU32) {
                last = self.nodes.items[last].next_sibling;
            }
            self.nodes.items[last].next_sibling = child_id;
        }
        self.nodes.items[child_id].parent = parent_id;
    }

    fn getData(self: *const TreeType, id: u32) *const NodeData {
        return &self.nodes.items[id];
    }

    fn getNodeName(self: *const TreeType, node: NodeType) []const u8 {
        if (node.isNull()) return "";
        return self.getData(node.id).name;
    }

    fn childCount(self: *const TreeType, node: NodeType) u32 {
        if (node.isNull()) return 0;
        var count: u32 = 0;
        var child = self.getData(node.id).first_child;
        while (child != maxU32) {
            count += 1;
            child = self.getData(child).next_sibling;
        }
        return count;
    }

    fn childAt(self: *const TreeType, node: NodeType, index: u32) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        var child = self.getData(node.id).first_child;
        var i: u32 = 0;
        while (i < index) {
            if (child == maxU32) return NodeType.@"null"();
            child = self.getData(child).next_sibling;
            i += 1;
        }
        if (child == maxU32) return NodeType.@"null"();
        return .{ .id = child, .tree = self };
    }

    fn namedChildCount(self: *const TreeType, node: NodeType) u32 {
        if (node.isNull()) return 0;
        var count: u32 = 0;
        var child = self.getData(node.id).first_child;
        while (child != maxU32) {
            if (self.getData(child).named) count += 1;
            child = self.getData(child).next_sibling;
        }
        return count;
    }

    fn namedChild(self: *const TreeType, node: NodeType, index: u32) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        var child = self.getData(node.id).first_child;
        var i: u32 = 0;
        while (child != maxU32) {
            if (self.getData(child).named) {
                if (i == index) return .{ .id = child, .tree = self };
                i += 1;
            }
            child = self.getData(child).next_sibling;
        }
        return NodeType.@"null"();
    }

    fn childByFieldName(self: *const TreeType, node: NodeType, name: []const u8) ?NodeType {
        if (node.isNull()) return null;
        var child = self.getData(node.id).first_child;
        while (child != maxU32) {
            const fn_ = self.getData(child).field_name;
            if (fn_) |f| {
                if (std.mem.eql(u8, f, name)) return .{ .id = child, .tree = self };
            }
            child = self.getData(child).next_sibling;
        }
        return null;
    }

    fn nextSibling(self: *const TreeType, node: NodeType) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        const ns = self.getData(node.id).next_sibling;
        if (ns == maxU32) return NodeType.@"null"();
        return .{ .id = ns, .tree = self };
    }

    fn prevSibling(self: *const TreeType, node: NodeType) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        const parent_id = self.getData(node.id).parent;
        if (parent_id == maxU32) return NodeType.@"null"();
        var child = self.getData(parent_id).first_child;
        var prev = maxU32;
        while (child != maxU32 and child != node.id) {
            prev = child;
            child = self.getData(child).next_sibling;
        }
        if (prev == maxU32) return NodeType.@"null"();
        return .{ .id = prev, .tree = self };
    }

    fn namedNextSibling(self: *const TreeType, node: NodeType) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        var next = self.getData(node.id).next_sibling;
        while (next != maxU32) {
            if (self.getData(next).named) return .{ .id = next, .tree = self };
            next = self.getData(next).next_sibling;
        }
        return NodeType.@"null"();
    }

    fn namedPrevSibling(self: *const TreeType, node: NodeType) NodeType {
        if (node.isNull()) return NodeType.@"null"();
        const parent_id = self.getData(node.id).parent;
        if (parent_id == maxU32) return NodeType.@"null"();
        var child = self.getData(parent_id).first_child;
        var prev = maxU32;
        while (child != maxU32 and child != node.id) {
            if (self.getData(child).named) prev = child;
            child = self.getData(child).next_sibling;
        }
        if (prev == maxU32) return NodeType.@"null"();
        return .{ .id = prev, .tree = self };
    }

    fn root(self: *const TreeType) NodeType {
        if (self.nodes.items.len == 0) return NodeType.@"null"();
        return .{ .id = 0, .tree = self };
    }
};

const NodeData = struct {
    name: []const u8,
    start_byte: u32,
    end_byte: u32,
    first_child: u32,
    next_sibling: u32,
    parent: u32,
    named: bool,
    field_name: ?[]const u8,
};

// --- Lexer ---

const TokenType = enum {
    WORD,
    ASSIGNMENT_WORD,
    SEMICOLON,
    AMPERSAND,
    PIPE,
    NEWLINE,
    AND_IF,
    OR_IF,
    GREAT,
    LESS,
    DGREAT,
    DLESS,
    LESSAND,
    GREATAND,
    DLESSDASH,
    LESSLESS,
    CLOBBER,
    ANDGREAT,
    LPAREN,
    RPAREN,
    LBRACE,
    RBRACE,
    BANG,
    DSEMI,
    DSDEMI,
    DSLSEMI,
    DBL_LPAREN,
    DBL_RPAREN,
    DBL_LBRACKET,
    DBL_RBRACKET,
    LBRACKET,
    RBRACKET,
    IF,
    THEN,
    ELSE,
    ELIF,
    FI,
    FOR,
    WHILE,
    UNTIL,
    DO,
    DONE,
    IN,
    SELECT,
    CASE,
    ESAC,
    FUNCTION,
    TIME,
    EOF,
};

const Token = struct {
    type: TokenType,
    start: u32,
    end: u32,
    is_assignment: bool,
};

// Regex-based tokenizer
const token_pattern =
    "&&|\\|\\||;;|;&|;;&|" ++
    ">>|<<|<&|>&|<<-|<<<|>\\||&>|" ++
    "\\[\\[[ \\t]*|\\]\\]|" ++
    "\\$\\(\\([^)]*\\)\\)|\\$\\([^)]*\\)|\\$\\{[^}]*\\}|" ++
    "\\$[a-zA-Z_][a-zA-Z0-9_]*|\\$[?$!#@*0-9-]|" ++
    "'[^']*'|\"[^\"]*\"|" ++
    "[0-9]+|" ++
    "[a-zA-Z_.][a-zA-Z0-9_.]*|" ++
    "[^]\\\\[;&|<>(){}! ]+|" ++
    "[][;|&(){}!<>]|" ++
    ".";

var lex_regex_mem: [512]u8 align(16) = undefined;
var lex_regex_init: bool = false;

fn initLexer() void {
    const ret = c.regcomp(@ptrCast(&lex_regex_mem), token_pattern, c.REG_EXTENDED);
    if (ret != 0) @panic("Failed to compile lexer regex");
    lex_regex_init = true;
}

fn deinitLexer() void {
    if (lex_regex_init) {
        c.regfree(@ptrCast(&lex_regex_mem));
        lex_regex_init = false;
    }
}

fn classifyToken(text: []const u8) TokenType {
    if (text.len == 1) return switch (text[0]) {
        ';' => .SEMICOLON,
        '|' => .PIPE,
        '&' => .AMPERSAND,
        '(' => .LPAREN,
        ')' => .RPAREN,
        '{' => .LBRACE,
        '}' => .RBRACE,
        '!' => .BANG,
        '<' => .LESS,
        '>' => .GREAT,
        '[' => .LBRACKET,
        ']' => .RBRACKET,
        else => .WORD,
    };

    if (std.mem.eql(u8, text, "&&")) return .AND_IF;
    if (std.mem.eql(u8, text, "||")) return .OR_IF;
    if (std.mem.eql(u8, text, ";;")) return .DSEMI;
    if (std.mem.eql(u8, text, ";&")) return .DSDEMI;
    if (std.mem.eql(u8, text, ";;&")) return .DSLSEMI;
    if (std.mem.eql(u8, text, ">>")) return .DGREAT;
    if (std.mem.eql(u8, text, "<<")) return .DLESS;
    if (std.mem.eql(u8, text, "<&")) return .LESSAND;
    if (std.mem.eql(u8, text, ">&")) return .GREATAND;
    if (std.mem.eql(u8, text, "<<-")) return .DLESSDASH;
    if (std.mem.eql(u8, text, "<<<")) return .LESSLESS;
    if (std.mem.eql(u8, text, ">|")) return .CLOBBER;
    if (std.mem.eql(u8, text, "&>")) return .ANDGREAT;
    if (std.mem.startsWith(u8, text, "[[")) return .DBL_LBRACKET;
    if (std.mem.eql(u8, text, "]]")) return .DBL_RBRACKET;

    return .WORD;
}

const ParserState = struct {
    source: [:0]const u8,
    pos: u32,
    allocator: std.mem.Allocator,
    tree: *TreeType,
    tok: Token,
    peek: Token,
    have_peek: bool,
    next_is_statement_start: bool,

    fn tokText(self: *const ParserState, tok: Token) []const u8 {
        return self.source[tok.start..tok.end];
    }

    fn nextTok(self: *ParserState) void {
        if (self.have_peek) {
            self.have_peek = false;
            self.tok = self.peek;
        } else {
            self.tok = self.lex();
        }
    }

    fn peekTok(self: *ParserState) Token {
        if (!self.have_peek) {
            self.peek = self.lex();
            self.have_peek = true;
        }
        return self.peek;
    }

    fn hasMoreTokens(self: *ParserState) bool {
        if (self.have_peek and self.peek.type == TokenType.EOF) return false;
        if (self.tok.type == TokenType.EOF and !self.have_peek) return false;
        return true;
    }

    fn lex(self: *ParserState) Token {
        const s = self.source;
        while (self.pos < s.len) {
            const start = self.pos;
            const ch = s[start];

            if (ch == ' ' or ch == '\t' or ch == '\r') {
                self.pos += 1;
                continue;
            }

            if (ch == '#') {
                self.pos += 1;
                while (self.pos < s.len and s[self.pos] != '\n') {
                    self.pos += 1;
                }
                continue;
            }

            if (ch == '\n') {
                self.pos += 1;
                return .{ .type = .NEWLINE, .start = @intCast(start), .end = @intCast(self.pos), .is_assignment = false };
            }

            var match: c.regmatch_t = undefined;
            const ret = c.regexec(@ptrCast(&lex_regex_mem), s.ptr + start, 1, &match, 0);
            if (ret != 0 or match.rm_so != 0 or match.rm_eo <= 0) {
                self.pos += 1;
                continue;
            }

            const match_len = @as(u32, @intCast(match.rm_eo));
            self.pos = start + match_len;
            const text = s[start..self.pos];

            const tok_type = classifyToken(text);

            if (tok_type == .WORD) {
                if (self.next_is_statement_start and isKeyword(text)) {
                    return .{ .type = keywordToTokenType(text), .start = @intCast(start), .end = @intCast(self.pos), .is_assignment = false };
                }
                return .{ .type = .WORD, .start = @intCast(start), .end = @intCast(self.pos), .is_assignment = isAssignmentWord(text) };
            }

            return .{ .type = tok_type, .start = @intCast(start), .end = @intCast(self.pos), .is_assignment = false };
        }

        return .{ .type = .EOF, .start = @intCast(self.pos), .end = @intCast(self.pos), .is_assignment = false };
    }
};

fn isAssignmentWord(text: []const u8) bool {
    if (text.len == 0) return false;
    if (text[0] >= '0' and text[0] <= '9') return false;
    var eq_pos: ?usize = null;
    for (text, 0..) |ch, i| {
        if (ch == '=') {
            if (i > 0) eq_pos = i;
            break;
        }
        if (i == 0) {
            if (!((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_')) return false;
        } else {
            if (!((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_')) return false;
        }
    }
    return eq_pos != null;
}

fn isKeyword(text: []const u8) bool {
    const keywords = comptime [_][]const u8{
        "if", "then", "else", "elif", "fi",
        "for", "while", "until", "do", "done",
        "in", "select", "case", "esac",
        "function", "time", "!",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return true;
    }
    return false;
}

fn keywordToTokenType(text: []const u8) TokenType {
    if (std.mem.eql(u8, text, "if")) return .IF;
    if (std.mem.eql(u8, text, "then")) return .THEN;
    if (std.mem.eql(u8, text, "else")) return .ELSE;
    if (std.mem.eql(u8, text, "elif")) return .ELIF;
    if (std.mem.eql(u8, text, "fi")) return .FI;
    if (std.mem.eql(u8, text, "for")) return .FOR;
    if (std.mem.eql(u8, text, "while")) return .WHILE;
    if (std.mem.eql(u8, text, "until")) return .UNTIL;
    if (std.mem.eql(u8, text, "do")) return .DO;
    if (std.mem.eql(u8, text, "done")) return .DONE;
    if (std.mem.eql(u8, text, "in")) return .IN;
    if (std.mem.eql(u8, text, "select")) return .SELECT;
    if (std.mem.eql(u8, text, "case")) return .CASE;
    if (std.mem.eql(u8, text, "esac")) return .ESAC;
    if (std.mem.eql(u8, text, "function")) return .FUNCTION;
    if (std.mem.eql(u8, text, "time")) return .TIME;
    if (std.mem.eql(u8, text, "!")) return .BANG;
    return .WORD;
}

fn isAllDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn isNumber(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text, 0..) |ch, i| {
        if (i == 0 and ch == '-') continue;
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn tokText(source: [:0]const u8, tok: Token) []const u8 {
    return source[tok.start..tok.end];
}

fn getLastChild(tree: *TreeType, id: u32) u32 {
    var child = tree.getData(id).first_child;
    var last = child;
    while (child != maxU32) {
        last = child;
        child = tree.getData(child).next_sibling;
    }
    return last;
}

fn getLastByte(tree: *TreeType, id: u32) u32 {
    var last: u32 = 0;
    var child = tree.getData(id).first_child;
    while (child != maxU32) {
        const end = tree.getData(child).end_byte;
        if (end > last) last = end;
        child = tree.getData(child).next_sibling;
    }
    return last;
}

fn makeWordNode(ps: *ParserState, tok: Token) u32 {
    const text = tokText(ps.source, tok);
    const start = tok.start;
    const end = tok.end;

    var node_name: []const u8 = "word";

    if (text.len >= 2) {
        if (text[0] == '\'' and text[text.len - 1] == '\'') {
            node_name = "raw_string";
        } else if (text[0] == '"' and text[text.len - 1] == '"') {
            node_name = "string";
        }
    }

    if (text.len >= 1 and text[0] == '$') {
        if (text.len > 1 and text[1] != '{' and text[1] != '(') {
            node_name = "simple_expansion";
        } else {
            node_name = "expansion";
        }
    }

    if (isNumber(text) and std.mem.eql(u8, node_name, "word")) {
        node_name = "number";
    }

    return ps.tree.addNode(node_name, start, end, true, null);
}

fn isRedirectToken(t: TokenType) bool {
    return switch (t) {
        .GREAT, .LESS, .DGREAT, .DLESS, .LESSAND, .GREATAND,
        .DLESSDASH, .LESSLESS, .CLOBBER, .ANDGREAT => true,
        else => false,
    };
}

// --- Parsing ---

fn parseProgram(ps: *ParserState) u32 {
    const start: u32 = 0;
    const prog_id = ps.tree.addNode("program", start, @intCast(ps.source.len), true, null);

    // Tokenize the entire input first
    ps.next_is_statement_start = true;
    ps.nextTok();

    while (ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }

        if (ps.tok.type == .WORD) {
            const text = ps.tokText(ps.tok);
            if (std.mem.eql(u8, text, ";;")) {
                break;
            }
        }

        // Parse statement
        const stmt_id = parseStatement(ps);
        if (stmt_id == maxU32) break;
        ps.tree.setChildLink(prog_id, stmt_id);

        // Handle separators after statement
        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            const sep_name = if (ps.tok.type == .SEMICOLON) ";" else if (ps.tok.type == .AMPERSAND) "&" else if (ps.tok.type == .DSEMI) ";;" else "";
            if (sep_name.len > 0) {
                const sep_node = ps.tree.addNode(sep_name, ps.tok.start, ps.tok.end, false, null);
                ps.tree.setChildLink(prog_id, sep_node);
            }
            ps.nextTok();
        } else if (ps.tok.type == .EOF) {
            break;
        } else {
            break;
        }
    }

    return prog_id;
}

fn parseStatement(ps: *ParserState) u32 {
    ps.next_is_statement_start = true;

    const tok = ps.tok;

    if (tok.type == .EOF or tok.type == .NEWLINE or tok.type == .SEMICOLON or tok.type == .AMPERSAND) {
        return maxU32;
    }

    // Parse the initial command (compound or simple)
    const result_id = parseCommandOrCompound(ps);
    if (result_id == maxU32) return maxU32;

    // Handle && and || for ALL command types (compound, simple, negated)
    if (ps.tok.type == .AND_IF or ps.tok.type == .OR_IF) {
        const first_start = ps.tree.getData(result_id).start_byte;
        var list_end = ps.tree.getData(result_id).end_byte;
        const list_id = ps.tree.addNode("list", first_start, 0, true, null);

        // Adopt the first command as first child
        ps.tree.nodes.items[result_id].parent = list_id;
        if (ps.tree.getData(list_id).first_child == maxU32) {
            ps.tree.nodes.items[list_id].first_child = result_id;
        }

        while (ps.tok.type == .AND_IF or ps.tok.type == .OR_IF) {
            const op_name = if (ps.tok.type == .AND_IF) "&&" else "||";
            const op_id = ps.tree.addNode(op_name, ps.tok.start, ps.tok.end, false, null);
            const op_end = ps.tok.end;
            ps.nextTok();

            const rhs = parseCommand(ps);
            if (rhs != maxU32) {
                const rhs_end = ps.tree.getData(rhs).end_byte;

                // Find the last child in the list and append op + rhs
                var last_child: u32 = maxU32;
                {
                    var child = ps.tree.getData(list_id).first_child;
                    while (child != maxU32) {
                        last_child = child;
                        child = ps.tree.getData(child).next_sibling;
                    }
                }

                if (last_child != maxU32) {
                    ps.tree.nodes.items[last_child].next_sibling = op_id;
                } else {
                    ps.tree.nodes.items[list_id].first_child = op_id;
                }
                ps.tree.nodes.items[op_id].parent = list_id;
                ps.tree.nodes.items[op_id].next_sibling = rhs;
                ps.tree.nodes.items[rhs].parent = list_id;

                if (rhs_end > list_end) list_end = rhs_end;
                if (op_end > list_end) list_end = op_end;
            }
        }

        ps.tree.nodes.items[list_id].end_byte = list_end;
        return list_id;
    }

    return result_id;
}

fn parseCommandOrCompound(ps: *ParserState) u32 {
    const tok = ps.tok;

    // Check for compound commands that start with keywords
    if (tok.type == .LBRACE) return parseBraceGroup(ps);
    if (tok.type == .LPAREN) return parseSubshell(ps);
    if (tok.type == .DBL_LPAREN) return parseArithCmd(ps);
    if (tok.type == .DBL_LBRACKET) return parseTestCommand(ps);
    if (tok.type == .IF) return parseIf(ps);
    if (tok.type == .FOR) return parseFor(ps);
    if (tok.type == .WHILE or tok.type == .UNTIL) return parseWhile(ps);
    if (tok.type == .CASE) return parseCase(ps);
    if (tok.type == .FUNCTION) return parseFunctionDef(ps);

    if (tok.type == .WORD) {
        const text = ps.tokText(tok);
        if (std.mem.eql(u8, text, "declare") or std.mem.eql(u8, text, "typeset") or
            std.mem.eql(u8, text, "local") or std.mem.eql(u8, text, "export") or
            std.mem.eql(u8, text, "readonly"))
        {
            return parseDeclaration(ps);
        }
        if (std.mem.eql(u8, text, "unset")) {
            return parseUnset(ps);
        }
        // Check for function definition: name() { ... }
        // Look at source bytes directly to check for () after the word
        var check_pos = ps.tok.end;
        while (check_pos < ps.source.len and (ps.source[check_pos] == ' ' or ps.source[check_pos] == '\t')) {
            check_pos += 1;
        }
        if (check_pos + 1 < ps.source.len and ps.source[check_pos] == '(' and ps.source[check_pos + 1] == ')') {
            return parseFunctionDefWithoutKeyword(ps);
        }
    }

    if (tok.type == .BANG) {
        ps.nextTok();
        const cmd_id = parseCommand(ps);
        if (cmd_id == maxU32) return maxU32;
        const neg_id = ps.tree.addNode("negated_command", tok.start, ps.tree.getData(cmd_id).end_byte, true, null);
        ps.tree.setChildLink(neg_id, cmd_id);
        return neg_id;
    }

    // Parse simple command
    return parseCommand(ps);
}

fn parseCommand(ps: *ParserState) u32 {
    const start_byte = ps.tok.start;

    var redirects = std.ArrayListAligned(u32, null).empty;
    defer redirects.deinit(ps.allocator);
    var assignments = std.ArrayListAligned(u32, null).empty;
    defer assignments.deinit(ps.allocator);
    var words = std.ArrayListAligned(u32, null).empty;
    defer words.deinit(ps.allocator);

    // Parse prefixes (variable assignments and redirects)
    while (true) {
        if (ps.tok.type == .WORD and ps.tok.is_assignment) {
            const a_id = makeWordNode(ps, ps.tok);
            ps.tree.nodes.items[a_id].name = ps.allocator.dupe(u8, "variable_assignment") catch @panic("OOM");
            assignments.append(ps.allocator, a_id) catch @panic("OOM");
            ps.nextTok();
        } else if (isRedirectToken(ps.tok.type)) {
            const r_id = parseRedirect(ps);
            if (r_id != maxU32) {
                redirects.append(ps.allocator, r_id) catch @panic("OOM");
            }
        } else {
            break;
        }
    }

    // Parse command word and arguments
    while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
        // Check if this is a file descriptor prefix (digit followed by redirect operator)
        const txt = ps.tokText(ps.tok);
        if (isAllDigits(txt) and ps.peekTok().type != .EOF) {
            const next_tt = ps.peekTok().type;
            if (isRedirectToken(next_tt)) {
                break; // Don't consume as word, let redirect loop handle it
            }
        }
        const w_id = makeWordNode(ps, ps.tok);
        words.append(ps.allocator, w_id) catch @panic("OOM");
        ps.nextTok();
    }

    // Parse more redirects (including fd-redirects like "2>&1")
    while (true) {
        if (isRedirectToken(ps.tok.type)) {
            const r_id = parseRedirect(ps);
            if (r_id != maxU32) {
                redirects.append(ps.allocator, r_id) catch @panic("OOM");
            }
        } else if (ps.tok.type == .WORD) {
            const txt = ps.tokText(ps.tok);
            if (isAllDigits(txt) and ps.peekTok().type != .EOF) {
                const next_tt = ps.peekTok().type;
                if (isRedirectToken(next_tt)) {
                    // This is a file descriptor prefix, e.g., "2>" or "2>&1"
                    const fd_id = ps.tree.addNode("file_descriptor", ps.tok.start, ps.tok.end, true, null);
                    ps.nextTok(); // consume the fd number
                    const r_id = parseRedirect(ps);
                    if (r_id != maxU32) {
                        // Insert fd as first child of the redirect
                        const old_first = ps.tree.getData(r_id).first_child;
                        ps.tree.nodes.items[r_id].first_child = fd_id;
                        ps.tree.nodes.items[fd_id].next_sibling = old_first;
                        ps.tree.nodes.items[fd_id].parent = r_id;
                        redirects.append(ps.allocator, r_id) catch @panic("OOM");
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        } else {
            break;
        }
    }

    // Check for pipe
    if (ps.tok.type == .PIPE) {
        return parsePipeline(ps, start_byte, assignments, words, redirects);
    }

    // No more tokens needed - build the AST
    const has_words = words.items.len > 0;
    const has_assignments = assignments.items.len > 0;
    const has_redirects = redirects.items.len > 0;

    if (!has_words and !has_assignments) return maxU32;

    // Calculate end byte
    var end_byte: u32 = start_byte;
    if (has_words) {
        end_byte = ps.tree.getData(words.items[words.items.len - 1]).end_byte;
    }
    if (has_assignments) {
        const a_end = ps.tree.getData(assignments.items[assignments.items.len - 1]).end_byte;
        if (a_end > end_byte) end_byte = a_end;
    }
    if (has_redirects) {
        for (redirects.items) |r| {
            const r_end = ps.tree.getData(r).end_byte;
            if (r_end > end_byte) end_byte = r_end;
        }
    }

    // Build the result node
    if (has_redirects) {
        var inner_id: u32 = maxU32;
        if (has_words) {
            const simple_id = ps.tree.addNode("simple_command", start_byte, end_byte, true, null);
            for (assignments.items) |a| ps.tree.setChildLink(simple_id, a);
            for (words.items) |w| ps.tree.setChildLink(simple_id, w);
            inner_id = simple_id;
        } else if (has_assignments) {
            inner_id = assignments.items[0];
            for (1..assignments.items.len) |i| {
                ps.tree.setChildLink(inner_id, assignments.items[i]);
            }
        }
        if (inner_id == maxU32) return maxU32;

        const redirect_cmd_id = ps.tree.addNode("redirected_statement", start_byte, end_byte, true, null);
        ps.tree.setChildLink(redirect_cmd_id, inner_id);
        for (redirects.items) |r| ps.tree.setChildLink(redirect_cmd_id, r);
        ps.tree.nodes.items[redirect_cmd_id].end_byte = end_byte;
        return redirect_cmd_id;
    }

    if (has_words) {
        if (has_assignments) {
            const simple_id = ps.tree.addNode("simple_command", start_byte, end_byte, true, null);
            for (assignments.items) |a| ps.tree.setChildLink(simple_id, a);
            for (words.items) |w| ps.tree.setChildLink(simple_id, w);
            return simple_id;
        }
        const simple_id = ps.tree.addNode("simple_command", start_byte, end_byte, true, null);
        for (words.items) |w| ps.tree.setChildLink(simple_id, w);
        return simple_id;
    }

    if (has_assignments) {
        if (assignments.items.len == 1) return assignments.items[0];
        const assign_list = ps.tree.addNode("variable_assignments", start_byte, end_byte, true, null);
        for (assignments.items) |a| ps.tree.setChildLink(assign_list, a);
        return assign_list;
    }

    return maxU32;
}

fn parsePipeline(ps: *ParserState, start_byte: u32, assignments: anytype, words: anytype, redirects: anytype) u32 {
    _ = redirects;

    var cmd_ids = std.ArrayListAligned(u32, null).empty;
    defer cmd_ids.deinit(ps.allocator);

    // Build first command from already-parsed parts
    if (words.items.len > 0 or assignments.items.len > 0) {
        const pipe_start = if (words.items.len > 0) ps.tree.getData(words.items[0]).start_byte else
            ps.tree.getData(assignments.items[0]).start_byte;
        const pipe_end = if (words.items.len > 0) ps.tree.getData(words.items[words.items.len - 1]).end_byte else
            ps.tree.getData(assignments.items[assignments.items.len - 1]).end_byte;
        const cmd_id = ps.tree.addNode("simple_command", pipe_start, pipe_end, true, null);
        for (assignments.items) |a| ps.tree.setChildLink(cmd_id, a);
        for (words.items) |w| ps.tree.setChildLink(cmd_id, w);
        cmd_ids.append(ps.allocator, cmd_id) catch @panic("OOM");
    }

    // Consume the pipe token
    _ = ps.tok;
    ps.nextTok();

    // Parse remaining pipe stages
    while (true) {
        var stage_assign = std.ArrayListAligned(u32, null).empty;
        defer stage_assign.deinit(ps.allocator);
        var stage_words = std.ArrayListAligned(u32, null).empty;
        defer stage_words.deinit(ps.allocator);

        while (ps.tok.type == .WORD and ps.tok.is_assignment) {
            const a_id = makeWordNode(ps, ps.tok);
            ps.tree.nodes.items[a_id].name = ps.allocator.dupe(u8, "variable_assignment") catch @panic("OOM");
            stage_assign.append(ps.allocator, a_id) catch @panic("OOM");
            ps.nextTok();
        }

        while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
            const w_id = makeWordNode(ps, ps.tok);
            stage_words.append(ps.allocator, w_id) catch @panic("OOM");
            ps.nextTok();
        }

        if (stage_words.items.len > 0 or stage_assign.items.len > 0) {
            const s_start = ps.tree.getData(stage_words.items[0]).start_byte;
            const s_end = ps.tree.getData(stage_words.items[stage_words.items.len - 1]).end_byte;
            const cmd_id = ps.tree.addNode("simple_command", s_start, s_end, true, null);
            for (stage_assign.items) |a| ps.tree.setChildLink(cmd_id, a);
            for (stage_words.items) |w| ps.tree.setChildLink(cmd_id, w);
            cmd_ids.append(ps.allocator, cmd_id) catch @panic("OOM");
        }

        if (ps.tok.type == .PIPE) {
            ps.nextTok();
        } else {
            break;
        }
    }

    if (cmd_ids.items.len == 0) return maxU32;

    const end_byte = ps.tree.getData(cmd_ids.items[cmd_ids.items.len - 1]).end_byte;
    const pipeline_id = ps.tree.addNode("pipeline", start_byte, end_byte, true, null);
    for (cmd_ids.items) |cid| {
        ps.tree.setChildLink(pipeline_id, cid);
    }
    return pipeline_id;
}

fn parseRedirect(ps: *ParserState) u32 {
    const op_type = ps.tok.type;
    const op_text = ps.tokText(ps.tok);
    const op_node = ps.tree.addNode(op_text, ps.tok.start, ps.tok.end, false, null);
    ps.nextTok();

    if (ps.tok.type != .WORD and ps.tok.type != .ASSIGNMENT_WORD) {
        return maxU32;
    }

    const target_id = makeWordNode(ps, ps.tok);
    ps.nextTok();

    const is_heredoc = op_type == .DLESS or op_type == .DLESSDASH;

    if (is_heredoc) {
        const heredoc_redirect_id = ps.tree.addNode("heredoc_redirect", op_node, 0, true, null);
        // Fix start
        ps.tree.nodes.items[heredoc_redirect_id].start_byte = ps.tree.getData(op_node).start_byte;
        ps.tree.nodes.items[heredoc_redirect_id].end_byte = ps.tree.getData(target_id).end_byte;
        ps.tree.setChildLink(heredoc_redirect_id, op_node);
        ps.tree.setChildLink(heredoc_redirect_id, target_id);
        return heredoc_redirect_id;
    }

    const file_redirect_id = ps.tree.addNode("file_redirect", ps.tree.getData(op_node).start_byte, ps.tree.getData(target_id).end_byte, true, null);
    ps.tree.setChildLink(file_redirect_id, op_node);
    ps.tree.setChildLink(file_redirect_id, target_id);
    return file_redirect_id;
}

// --- Compound commands ---

fn parseBraceGroup(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok();
    const ct_id = ps.tree.addNode("compound_statement", start, 0, true, null);

    while (ps.tok.type != .RBRACE and ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        ps.tree.setChildLink(ct_id, stmt);
    }

    const end = if (ps.tok.type == .RBRACE) blk: {
        const e = ps.tok.end;
        ps.nextTok();
        break :blk e;
    } else @as(u32, @intCast(ps.source.len));
    ps.tree.nodes.items[ct_id].end_byte = end;
    return ct_id;
}

fn parseSubshell(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok();
    const ss_id = ps.tree.addNode("subshell", start, 0, true, null);

    while (ps.tok.type != .RPAREN and ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        ps.tree.setChildLink(ss_id, stmt);
    }

    const end = if (ps.tok.type == .RPAREN) blk: {
        const e = ps.tok.end;
        ps.nextTok();
        break :blk e;
    } else @as(u32, @intCast(ps.source.len));
    ps.tree.nodes.items[ss_id].end_byte = end;
    return ss_id;
}

fn parseArithCmd(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok();
    const ct_id = ps.tree.addNode("compound_statement", start, 0, true, null);

    while (ps.tok.type != .DBL_RPAREN and ps.tok.type != .EOF) {
        if (ps.tok.type == .WORD) {
            const w_id = makeWordNode(ps, ps.tok);
            ps.tree.setChildLink(ct_id, w_id);
            ps.nextTok();
        } else {
            ps.nextTok();
        }
    }

    const end = if (ps.tok.type == .DBL_RPAREN) blk: {
        const e = ps.tok.end;
        ps.nextTok();
        break :blk e;
    } else @as(u32, @intCast(ps.source.len));
    ps.tree.nodes.items[ct_id].end_byte = end;
    return ct_id;
}

fn parseTestCommand(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok();

    var expr_tokens = std.ArrayListAligned(Token, null).empty;
    defer expr_tokens.deinit(ps.allocator);

    while (ps.tok.type != .DBL_RBRACKET and ps.tok.type != .EOF) {
        expr_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    const end = ps.tok.end;
    ps.nextTok();

    const tc_id = ps.tree.addNode("test_command", start, end, true, null);

    if (expr_tokens.items.len > 0) {
        const expr_id = buildTestExpr(ps, expr_tokens.items, 0, expr_tokens.items.len);
        if (expr_id != maxU32) {
            ps.tree.setChildLink(tc_id, expr_id);
        }
    }

    ps.tree.nodes.items[tc_id].end_byte = end;
    return tc_id;
}

fn buildTestExpr(ps: *ParserState, tokens: []const Token, start_idx: usize, end_idx: usize) u32 {
    if (start_idx >= end_idx) return maxU32;

    // Lowest precedence: || (OR)
    for (start_idx..end_idx) |i| {
        if (tokens[i].type == .OR_IF) {
            const left_id = buildTestExpr(ps, tokens, start_idx, i);
            if (left_id == maxU32) return maxU32;
            const op_id = ps.tree.addNode("||", tokens[i].start, tokens[i].end, false, null);
            const right_id = buildTestExpr(ps, tokens, i + 1, end_idx);
            if (right_id == maxU32) return maxU32;
            const bin_id = ps.tree.addNode("binary_expression",
                ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
            ps.tree.setChildLink(bin_id, left_id);
            ps.tree.setChildLink(bin_id, op_id);
            ps.tree.setChildLink(bin_id, right_id);
            return bin_id;
        }
    }

    // && (AND) - higher precedence than ||
    for (start_idx..end_idx) |i| {
        if (tokens[i].type == .AND_IF) {
            const left_id = buildTestExpr(ps, tokens, start_idx, i);
            if (left_id == maxU32) return maxU32;
            const op_id = ps.tree.addNode("&&", tokens[i].start, tokens[i].end, false, null);
            const right_id = buildTestExpr(ps, tokens, i + 1, end_idx);
            if (right_id == maxU32) return maxU32;
            const bin_id = ps.tree.addNode("binary_expression",
                ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
            ps.tree.setChildLink(bin_id, left_id);
            ps.tree.setChildLink(bin_id, op_id);
            ps.tree.setChildLink(bin_id, right_id);
            return bin_id;
        }
    }

    // No logical operators - parse as a primary expression
    return buildTestPrimary(ps, tokens, start_idx, end_idx);
}

fn buildTestPrimary(ps: *ParserState, tokens: []const Token, start_idx: usize, end_idx: usize) u32 {
    if (start_idx >= end_idx) return maxU32;

    // Handle parenthesized expression
    if (tokens[start_idx].type == .LPAREN) {
        var depth: u32 = 1;
        var i = start_idx + 1;
        while (i < end_idx and depth > 0) {
            if (tokens[i].type == .LPAREN) depth += 1;
            if (tokens[i].type == .RPAREN) {
                depth -= 1;
                if (depth == 0) {
                    const inner_id = buildTestExpr(ps, tokens, start_idx + 1, i);
                    if (inner_id == maxU32) return maxU32;
                    const paren_id = ps.tree.addNode("parenthesized_expression",
                        tokens[start_idx].start, tokens[i].end, true, null);
                    ps.tree.setChildLink(paren_id, inner_id);
                    return paren_id;
                }
            }
            i += 1;
        }
    }

    // Handle unary ! (negation) - binds to the next primary
    // But NOT if followed by = (that's != binary operator)
    if (start_idx < end_idx) {
        const first_text = tokText(ps.source, tokens[start_idx]);
        if (std.mem.eql(u8, first_text, "!")) {
            const is_neq = start_idx + 1 < end_idx and
                tokens[start_idx + 1].type == .WORD and
                std.mem.eql(u8, tokText(ps.source, tokens[start_idx + 1]), "=");
            if (!is_neq) {
                const op_token = tokens[start_idx];
                const op_id = ps.tree.addNode(first_text, op_token.start, op_token.end, false, null);
                const operand_id = buildTestPrimary(ps, tokens, start_idx + 1, end_idx);
                if (operand_id == maxU32) return maxU32;
                const unary_id = ps.tree.addNode("unary_expression",
                    tokens[start_idx].start, ps.tree.getData(operand_id).end_byte, true, null);
                ps.tree.setChildLink(unary_id, op_id);
                ps.tree.setChildLink(unary_id, operand_id);
                return unary_id;
            }
        }
    }

    // Handle unary test operators (-z, -n, -f, -d, etc.) - these take ONE operand word
    if (start_idx + 1 <= end_idx) {
        const first_text = tokText(ps.source, tokens[start_idx]);
        if (isUnaryOp(first_text)) {
            const op_token = tokens[start_idx];
            const op_id = ps.tree.addNode(first_text, op_token.start, op_token.end, false, null);
            const operand_id = buildTestPrimary(ps, tokens, start_idx + 1, end_idx);
            if (operand_id == maxU32) return maxU32;
            const unary_id = ps.tree.addNode("unary_expression",
                tokens[start_idx].start, ps.tree.getData(operand_id).end_byte, true, null);
            ps.tree.setChildLink(unary_id, op_id);
            ps.tree.setChildLink(unary_id, operand_id);
            return unary_id;
        }
    }

    // Handle binary comparison operators (==, !=, -eq, -ne, etc.)
    // These have higher precedence than &&/||, so we only look within this primary
    // Also handles < (LESS), > (GREAT), and != (BANG + WORD("="))
    for (start_idx..end_idx) |i| {
        // Check for != (lexed as BANG + WORD "=")
        if (tokens[i].type == .BANG and i + 1 < end_idx and
            tokens[i + 1].type == .WORD and
            std.mem.eql(u8, tokText(ps.source, tokens[i + 1]), "="))
        {
            const left_id = buildTestPrimary(ps, tokens, start_idx, i);
            if (left_id == maxU32) return maxU32;
            const op_text = "!=";
            const op_id = ps.tree.addNode(op_text, tokens[i].start, tokens[i + 1].end, false, null);
            const right_id = buildTestPrimary(ps, tokens, i + 2, end_idx);
            if (right_id == maxU32) return maxU32;
            const bin_id = ps.tree.addNode("binary_expression",
                ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
            ps.tree.setChildLink(bin_id, left_id);
            ps.tree.setChildLink(bin_id, op_id);
            ps.tree.setChildLink(bin_id, right_id);
            return bin_id;
        }

        // Check for < (lexed as LESS)
        if (tokens[i].type == .LESS) {
            const left_id = buildTestPrimary(ps, tokens, start_idx, i);
            if (left_id == maxU32) return maxU32;
            const op_id = ps.tree.addNode("<", tokens[i].start, tokens[i].end, false, null);
            const right_id = buildTestPrimary(ps, tokens, i + 1, end_idx);
            if (right_id == maxU32) return maxU32;
            const bin_id = ps.tree.addNode("binary_expression",
                ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
            ps.tree.setChildLink(bin_id, left_id);
            ps.tree.setChildLink(bin_id, op_id);
            ps.tree.setChildLink(bin_id, right_id);
            return bin_id;
        }

        // Check for > (lexed as GREAT)
        if (tokens[i].type == .GREAT) {
            const left_id = buildTestPrimary(ps, tokens, start_idx, i);
            if (left_id == maxU32) return maxU32;
            const op_id = ps.tree.addNode(">", tokens[i].start, tokens[i].end, false, null);
            const right_id = buildTestPrimary(ps, tokens, i + 1, end_idx);
            if (right_id == maxU32) return maxU32;
            const bin_id = ps.tree.addNode("binary_expression",
                ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
            ps.tree.setChildLink(bin_id, left_id);
            ps.tree.setChildLink(bin_id, op_id);
            ps.tree.setChildLink(bin_id, right_id);
            return bin_id;
        }

        // Check for WORD-based binary operators (==, -eq, etc.)
        if (tokens[i].type == .WORD) {
            const txt = tokText(ps.source, tokens[i]);
            if (isBinaryOp(txt)) {
                const op_token = tokens[i];
                const left_id = buildTestPrimary(ps, tokens, start_idx, i);
                if (left_id == maxU32) return maxU32;
                const op_id = ps.tree.addNode(txt, op_token.start, op_token.end, false, null);
                const right_id = buildTestPrimary(ps, tokens, i + 1, end_idx);
                if (right_id == maxU32) return maxU32;
                const bin_id = ps.tree.addNode("binary_expression",
                    ps.tree.getData(left_id).start_byte, ps.tree.getData(right_id).end_byte, true, null);
                ps.tree.setChildLink(bin_id, left_id);
                ps.tree.setChildLink(bin_id, op_id);
                ps.tree.setChildLink(bin_id, right_id);
                return bin_id;
            }
        }
    }

    // Single operand - make a word node
    return makeWordNode(ps, tokens[start_idx]);
}

fn isUnaryOp(text: []const u8) bool {
    if (std.mem.eql(u8, text, "!")) return true;
    if (text.len == 2 and text[0] == '-') {
        return switch (text[1]) {
            'z', 'n', 'd', 'f', 'r', 'w', 'x', 'e', 's', 'L', 'b', 'c', 'G', 'k', 'O', 'p', 'S', 'N', 't', 'o', 'v', 'R' => true,
            else => false,
        };
    }
    return false;
}

fn isBinaryOp(text: []const u8) bool {
    return std.mem.eql(u8, text, "==") or std.mem.eql(u8, text, "!=") or
        std.mem.eql(u8, text, "=~") or std.mem.eql(u8, text, "=") or
        std.mem.eql(u8, text, "-eq") or std.mem.eql(u8, text, "-ne") or
        std.mem.eql(u8, text, "-lt") or std.mem.eql(u8, text, "-le") or
        std.mem.eql(u8, text, "-gt") or std.mem.eql(u8, text, "-ge") or
        std.mem.eql(u8, text, "<") or std.mem.eql(u8, text, ">") or
        std.mem.eql(u8, text, "-ef") or std.mem.eql(u8, text, "-nt") or
        std.mem.eql(u8, text, "-ot");
}

// --- If statement ---

fn parseIf(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'if'

    const if_id = ps.tree.addNode("if_statement", start, 0, true, null);

    // Parse condition - this is a statement that runs until 'then'
    // Collect tokens/statements until 'then'
    var cond_tokens = std.ArrayListAligned(Token, null).empty;
    defer cond_tokens.deinit(ps.allocator);
    var cond_words = std.ArrayListAligned(u32, null).empty;
    defer cond_words.deinit(ps.allocator);
    var found_then = false;

    while (ps.tok.type != .EOF) {
        if (ps.tok.type == .THEN) {
            found_then = true;
            ps.nextTok();
            break;
        }
        cond_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    if (!found_then) {
        ps.tree.nodes.items[if_id].end_byte = @intCast(ps.source.len);
        return if_id;
    }

    // Build condition from tokens
    const cond_id = buildConditionFromTokens(ps, cond_tokens.items);
    if (cond_id != maxU32) {
        ps.tree.setChildLink(if_id, cond_id);
    }

    // Parse body (statements until elif, else, fi)
    var body_statements = std.ArrayListAligned(u32, null).empty;
    defer body_statements.deinit(ps.allocator);

    while (ps.tok.type != .EOF and ps.tok.type != .ELIF and ps.tok.type != .ELSE and ps.tok.type != .FI) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        body_statements.append(ps.allocator, stmt) catch @panic("OOM");

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    if (body_statements.items.len > 0) {
        const body_id = createBodyNode(ps, body_statements.items);
        ps.tree.setChildLink(if_id, body_id);
    }

    // Parse elif and else clauses
    while (ps.tok.type == .ELIF) {
        const elif_id = parseElif(ps);
        if (elif_id != maxU32) {
            ps.tree.setChildLink(if_id, elif_id);
        }
    }

    if (ps.tok.type == .ELSE) {
        const else_id = parseElse(ps);
        if (else_id != maxU32) {
            ps.tree.setChildLink(if_id, else_id);
        }
    }

    // Expect fi
    if (ps.tok.type == .FI) {
        ps.tree.nodes.items[if_id].end_byte = ps.tok.end;
        ps.nextTok();
    } else {
        ps.tree.nodes.items[if_id].end_byte = @intCast(ps.source.len);
    }

    return if_id;
}

fn parseElif(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'elif'

    const elif_id = ps.tree.addNode("elif_clause", start, 0, true, null);

    // Parse condition until 'then'
    var cond_tokens = std.ArrayListAligned(Token, null).empty;
    defer cond_tokens.deinit(ps.allocator);
    var found_then = false;

    while (ps.tok.type != .EOF) {
        if (ps.tok.type == .THEN) {
            found_then = true;
            ps.nextTok();
            break;
        }
        cond_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    if (!found_then) return elif_id;

    const cond_id = buildConditionFromTokens(ps, cond_tokens.items);
    if (cond_id != maxU32) {
        ps.tree.setChildLink(elif_id, cond_id);
    }

    // Parse body
    var body_statements = std.ArrayListAligned(u32, null).empty;
    defer body_statements.deinit(ps.allocator);

    while (ps.tok.type != .EOF and ps.tok.type != .ELIF and ps.tok.type != .ELSE and ps.tok.type != .FI) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        body_statements.append(ps.allocator, stmt) catch @panic("OOM");

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    if (body_statements.items.len > 0) {
        const body_id = createBodyNode(ps, body_statements.items);
        ps.tree.setChildLink(elif_id, body_id);
    }

    ps.tree.nodes.items[elif_id].end_byte = ps.tok.start;
    return elif_id;
}

fn parseElse(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'else'

    const else_id = ps.tree.addNode("else_clause", start, 0, true, null);

    var body_statements = std.ArrayListAligned(u32, null).empty;
    defer body_statements.deinit(ps.allocator);

    while (ps.tok.type != .EOF and ps.tok.type != .FI) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        body_statements.append(ps.allocator, stmt) catch @panic("OOM");

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    if (body_statements.items.len > 0) {
        const body_id = createBodyNode(ps, body_statements.items);
        ps.tree.setChildLink(else_id, body_id);
    }

    ps.tree.nodes.items[else_id].end_byte = ps.tok.start;
    return else_id;
}

fn buildConditionFromTokens(ps: *ParserState, tokens: []const Token) u32 {
    if (tokens.len == 0) return maxU32;

    var word_ids = std.ArrayListAligned(u32, null).empty;
    defer word_ids.deinit(ps.allocator);

    for (tokens) |tok| {
        if (tok.type == .WORD or tok.type == .ASSIGNMENT_WORD) {
            const w_id = makeWordNode(ps, tok);
            word_ids.append(ps.allocator, w_id) catch @panic("OOM");
        }
    }

    if (word_ids.items.len == 0) return maxU32;

    const first_id = word_ids.items[0];
    if (word_ids.items.len == 1) return first_id;

    const start = ps.tree.getData(first_id).start_byte;
    const end = ps.tree.getData(word_ids.items[word_ids.items.len - 1]).end_byte;
    const cmd_id = ps.tree.addNode("simple_command", start, end, true, null);
    for (word_ids.items) |w| {
        ps.tree.setChildLink(cmd_id, w);
    }
    return cmd_id;
}

// --- For statement ---

fn parseFor(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'for'

    // Check for C-style for loop: for ((...; ...; ...))
    if (ps.tok.type == .DBL_LPAREN) {
        return parseCStyleFor(ps, start);
    }

    const for_id = ps.tree.addNode("for_statement", start, 0, true, null);

    // Get variable name
    if (ps.tok.type != .WORD) {
        ps.tree.nodes.items[for_id].end_byte = @intCast(ps.source.len);
        return for_id;
    }
    const var_name_id = makeWordNode(ps, ps.tok);
    ps.tree.nodes.items[var_name_id].name = ps.allocator.dupe(u8, "variable_name") catch @panic("OOM");
    ps.tree.setChildLink(for_id, var_name_id);
    ps.nextTok();

    // Check for 'in' keyword
    if (ps.tok.type == .IN) {
        ps.nextTok();

        // Parse word list
        while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
            const w_id = makeWordNode(ps, ps.tok);
            ps.tree.setChildLink(for_id, w_id);
            ps.nextTok();
        }

        // Skip ';' before 'do'
        if (ps.tok.type == .SEMICOLON) {
            ps.nextTok();
        }
    }

    // Expect 'do'
    if (ps.tok.type != .DO) {
        _ = ps.tok;
        ps.tree.nodes.items[for_id].end_byte = @intCast(ps.source.len);
        return for_id;
    }
    ps.nextTok();

    // Parse body (until 'done')
    var body_statements = std.ArrayListAligned(u32, null).empty;
    defer body_statements.deinit(ps.allocator);

    while (ps.tok.type != .DONE and ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        body_statements.append(ps.allocator, stmt) catch @panic("OOM");

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    if (body_statements.items.len > 0) {
        const body_id = createBodyNode(ps, body_statements.items);
        if (body_id != maxU32) {
            ps.tree.setChildLink(for_id, body_id);
        }
    }

    if (ps.tok.type == .DONE) {
        ps.tree.nodes.items[for_id].end_byte = ps.tok.end;
        ps.nextTok();
    }

    return for_id;
}

fn parseCStyleFor(ps: *ParserState, start: u32) u32 {
    ps.nextTok(); // skip ((
    const for_id = ps.tree.addNode("c_style_for_statement", start, 0, true, null);

    // Parse initializer
    var init_tokens = std.ArrayListAligned(Token, null).empty;
    defer init_tokens.deinit(ps.allocator);
    while (ps.tok.type != .EOF and ps.tok.type != .SEMICOLON and ps.tok.type != .DBL_RPAREN) {
        init_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    if (ps.tok.type == .SEMICOLON) ps.nextTok();

    // Parse condition
    var cond_tokens = std.ArrayListAligned(Token, null).empty;
    defer cond_tokens.deinit(ps.allocator);
    while (ps.tok.type != .EOF and ps.tok.type != .SEMICOLON and ps.tok.type != .DBL_RPAREN) {
        cond_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    if (ps.tok.type == .SEMICOLON) ps.nextTok();

    // Parse update
    var update_tokens = std.ArrayListAligned(Token, null).empty;
    defer update_tokens.deinit(ps.allocator);
    while (ps.tok.type != .EOF and ps.tok.type != .DBL_RPAREN) {
        update_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    // Skip ))
    if (ps.tok.type == .DBL_RPAREN) {
        ps.nextTok();
    } else {
        while (ps.tok.type != .DBL_RPAREN and ps.tok.type != .EOF) {
            ps.nextTok();
        }
        if (ps.tok.type == .DBL_RPAREN) ps.nextTok();
    }

    // Attach init/cond/update as field children
    if (init_tokens.items.len > 0) {
        const init_id = makeNodeSequence(ps.tree, init_tokens.items);
        if (init_id != maxU32) {
            ps.tree.nodes.items[init_id].field_name = ps.allocator.dupe(u8, "initializer") catch @panic("OOM");
            ps.tree.setChildLink(for_id, init_id);
        }
    }
    if (cond_tokens.items.len > 0) {
        const cond_id = makeNodeSequence(ps.tree, cond_tokens.items);
        if (cond_id != maxU32) {
            ps.tree.nodes.items[cond_id].field_name = ps.allocator.dupe(u8, "condition") catch @panic("OOM");
            ps.tree.setChildLink(for_id, cond_id);
        }
    }
    if (update_tokens.items.len > 0) {
        const update_id = makeNodeSequence(ps.tree, update_tokens.items);
        if (update_id != maxU32) {
            ps.tree.nodes.items[update_id].field_name = ps.allocator.dupe(u8, "update") catch @panic("OOM");
            ps.tree.setChildLink(for_id, update_id);
        }
    }

    // Skip ';' before 'do'
    if (ps.tok.type == .SEMICOLON) ps.nextTok();

    // Expect 'do'
    if (ps.tok.type == .DO) {
        ps.nextTok();

        var body_statements = std.ArrayListAligned(u32, null).empty;
        defer body_statements.deinit(ps.allocator);

        while (ps.tok.type != .DONE and ps.tok.type != .EOF) {
            if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
                ps.nextTok();
                continue;
            }
            const stmt = parseStatement(ps);
            if (stmt == maxU32) break;
            body_statements.append(ps.allocator, stmt) catch @panic("OOM");

            if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
                ps.nextTok();
            }
        }

        if (body_statements.items.len > 0) {
            const body_id = createBodyNode(ps, body_statements.items);
            if (body_id != maxU32) {
                ps.tree.nodes.items[body_id].field_name = ps.allocator.dupe(u8, "body") catch @panic("OOM");
                ps.tree.setChildLink(for_id, body_id);
            }
        }

        if (ps.tok.type == .DONE) {
            ps.tree.nodes.items[for_id].end_byte = ps.tok.end;
            ps.nextTok();
        }
    }

    return for_id;
}

fn makeNodeSequence(tree: *TreeType, tokens: []const Token) u32 {
    if (tokens.len == 0) return maxU32;
    if (tokens.len == 1) {
        const text = tokText(tree.source, tokens[0]);
        const name = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') "string"
            else if (text.len >= 2 and text[0] == '\'' and text[text.len - 1] == '\'') "raw_string"
            else if (text[0] == '$' and text.len > 1 and text[1] != '{' and text[1] != '(') "simple_expansion"
            else if (text[0] == '$') "expansion"
            else if (isNumber(text)) "number"
            else "word";
        return tree.addNode(name, tokens[0].start, tokens[0].end, true, null);
    }

    const start = tokens[0].start;
    const end = tokens[tokens.len - 1].end;
    return tree.addNode("word", start, end, true, null);
}

// --- While/Until statement ---

fn parseWhile(ps: *ParserState) u32 {
    const is_until = ps.tok.type == .UNTIL;
    const start = ps.tok.start;
    ps.nextTok();

    const while_id = ps.tree.addNode("while_statement", start, 0, true, null);

    // Parse condition (statements until 'do')
    var cond_tokens = std.ArrayListAligned(Token, null).empty;
    defer cond_tokens.deinit(ps.allocator);
    var cond_words = std.ArrayListAligned(u32, null).empty;
    defer cond_words.deinit(ps.allocator);
    var found_do = false;

    while (ps.tok.type != .EOF) {
        if (ps.tok.type == .DO) {
            found_do = true;
            ps.nextTok();
            break;
        }
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON) {
            ps.nextTok();
            continue;
        }
        cond_tokens.append(ps.allocator, ps.tok) catch @panic("OOM");
        ps.nextTok();
    }

    if (!found_do) return while_id;

    // Build condition from tokens
    // For the executor, the condition is the first named child
    // It expects: namedChild(0) = condition, namedChild(1) = body
    // We also need to include the "until"/"while" keyword for detection
    const until_keyword = ps.tree.addNode(if (is_until) "until" else "while", start, ps.tok.start, false, null);
    _ = until_keyword;

    if (cond_tokens.items.len > 0) {
        const cond_id = buildConditionFromTokens(ps, cond_tokens.items);
        if (cond_id != maxU32) {
            ps.tree.setChildLink(while_id, cond_id);
        }
    }

    // Parse body until 'done'
    var body_statements = std.ArrayListAligned(u32, null).empty;
    defer body_statements.deinit(ps.allocator);

    while (ps.tok.type != .DONE and ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE or ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        body_statements.append(ps.allocator, stmt) catch @panic("OOM");

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    if (body_statements.items.len > 0) {
        const body_id = createBodyNode(ps, body_statements.items);
        if (body_id != maxU32) {
            ps.tree.setChildLink(while_id, body_id);
        }
    }

    if (ps.tok.type == .DONE) {
        ps.tree.nodes.items[while_id].end_byte = ps.tok.end;
        ps.nextTok();
    } else {
        ps.tree.nodes.items[while_id].end_byte = @intCast(ps.source.len);
    }

    return while_id;
}

// --- Case statement ---

fn parseCase(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'case'

    const case_id = ps.tree.addNode("case_statement", start, 0, true, null);

    // Parse the value word
    if (ps.tok.type != .WORD and ps.tok.type != .ASSIGNMENT_WORD) {
        ps.tree.nodes.items[case_id].end_byte = @intCast(ps.source.len);
        return case_id;
    }
    const value_id = makeWordNode(ps, ps.tok);
    ps.tree.setChildLink(case_id, value_id);
    ps.nextTok();

    // Expect 'in'
    if (ps.tok.type != .IN) {
        _ = ps.tok;
        ps.tree.nodes.items[case_id].end_byte = @intCast(ps.source.len);
        return case_id;
    }
    ps.nextTok();

    // Skip newlines
    while (ps.tok.type == .NEWLINE) ps.nextTok();

    // Parse case items
    while (ps.tok.type != .ESAC and ps.tok.type != .EOF) {
        if (ps.tok.type == .NEWLINE) {
            ps.nextTok();
            continue;
        }

        const item_id = parseCaseItem(ps);
        if (item_id != maxU32) {
            ps.tree.setChildLink(case_id, item_id);
        }
    }

    if (ps.tok.type == .ESAC) {
        ps.tree.nodes.items[case_id].end_byte = ps.tok.end;
        ps.nextTok();
    }

    return case_id;
}

fn parseCaseItem(ps: *ParserState) u32 {
    const start = ps.tok.start;

    // Optional LPAREN
    if (ps.tok.type == .LPAREN) {
        ps.nextTok();
    }

    const item_id = ps.tree.addNode("case_item", start, 0, true, null);

    // Parse patterns (WORD tokens separated by PIPE)
    while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
        const pat_id = makeWordNode(ps, ps.tok);
        ps.tree.setChildLink(item_id, pat_id);
        ps.nextTok();

        if (ps.tok.type == .PIPE) {
            ps.nextTok();
            continue;
        }
        break;
    }

    // Expect RPAREN
    if (ps.tok.type == .RPAREN) {
        ps.nextTok();
    }

    // Parse body until ;; or ;& or ;;& or esac
    while (ps.tok.type != .DSEMI and ps.tok.type != .DSDEMI and ps.tok.type != .DSLSEMI and
           ps.tok.type != .ESAC and ps.tok.type != .EOF)
    {
        if (ps.tok.type == .NEWLINE) {
            ps.nextTok();
            continue;
        }
        const stmt = parseStatement(ps);
        if (stmt == maxU32) break;
        ps.tree.setChildLink(item_id, stmt);

        if (ps.tok.type == .SEMICOLON or ps.tok.type == .AMPERSAND or ps.tok.type == .NEWLINE) {
            ps.nextTok();
        }
    }

    const end = ps.tok.end;
    if (ps.tok.type == .DSEMI or ps.tok.type == .DSDEMI or ps.tok.type == .DSLSEMI) {
        ps.nextTok();
    }
    ps.tree.nodes.items[item_id].end_byte = end;
    return item_id;
}

// --- Function definition ---

fn parseFunctionDef(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok(); // skip 'function'

    // Get function name
    const name_id = makeWordNode(ps, ps.tok);
    ps.tree.nodes.items[name_id].name = ps.allocator.dupe(u8, "word") catch @panic("OOM");
    ps.nextTok();

    // Parse optional ()
    if (ps.tok.type == .LPAREN and ps.peekTok().type == .RPAREN) {
        ps.nextTok();
        ps.nextTok();
    }

    // Parse body (must be a compound statement with { })
    if (ps.tok.type != .LBRACE) {
        return maxU32;
    }

    const body_id = parseBraceGroup(ps);

    const fn_id = ps.tree.addNode("function_definition", start, ps.tree.getData(body_id).end_byte, true, null);
    ps.tree.setChildLink(fn_id, name_id);
    ps.tree.setChildLink(fn_id, body_id);
    return fn_id;
}

fn parseFunctionDefWithoutKeyword(ps: *ParserState) u32 {
    // name() { ... } style - called when we see a WORD followed by ()
    const start = ps.tok.start;
    const name_id = makeWordNode(ps, ps.tok);
    ps.nextTok(); // skip name

    // Skip ()
    if (ps.tok.type == .LPAREN) {
        ps.nextTok();
        if (ps.tok.type == .RPAREN) ps.nextTok();
    }

    if (ps.tok.type != .LBRACE) return maxU32;

    const body_id = parseBraceGroup(ps);

    const fn_id = ps.tree.addNode("function_definition", start, ps.tree.getData(body_id).end_byte, true, null);
    ps.tree.setChildLink(fn_id, name_id);
    ps.tree.setChildLink(fn_id, body_id);
    return fn_id;
}

// --- Declaration and unset ---

fn parseDeclaration(ps: *ParserState) u32 {
    const start = ps.tok.start;
    const cmd_text = ps.tokText(ps.tok);
    ps.nextTok();

    const cmd_id = ps.tree.addNode("declaration_command", start, 0, true, null);

    while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
        const w_id = makeWordNode(ps, ps.tok);
        if (ps.tok.is_assignment) {
            ps.tree.nodes.items[w_id].name = ps.allocator.dupe(u8, "variable_assignment") catch @panic("OOM");
        }
        ps.tree.setChildLink(cmd_id, w_id);
        ps.nextTok();
    }

    if (ps.tree.getData(cmd_id).first_child != maxU32) {
        ps.tree.nodes.items[cmd_id].end_byte = ps.tree.getData(getLastChild(ps.tree, cmd_id)).end_byte;
    } else {
        ps.tree.nodes.items[cmd_id].end_byte = start + @as(u32, @intCast(cmd_text.len));
    }

    return cmd_id;
}

fn parseUnset(ps: *ParserState) u32 {
    const start = ps.tok.start;
    ps.nextTok();

    const cmd_id = ps.tree.addNode("unset_command", start, 0, true, null);

    while (ps.tok.type == .WORD or ps.tok.type == .ASSIGNMENT_WORD) {
        const w_id = makeWordNode(ps, ps.tok);
        ps.tree.setChildLink(cmd_id, w_id);
        ps.nextTok();
    }

    if (ps.tree.getData(cmd_id).first_child != maxU32) {
        ps.tree.nodes.items[cmd_id].end_byte = ps.tree.getData(getLastChild(ps.tree, cmd_id)).end_byte;
    } else {
        ps.tree.nodes.items[cmd_id].end_byte = start + 5;
    }

    return cmd_id;
}

// --- Public API ---

var global_allocator: std.mem.Allocator = undefined;

pub fn init() void {
    initLexer();
}

pub fn deinit() void {
    deinitLexer();
}

pub fn parseString(source: [:0]const u8) ?*TreeType {
    const allocator = std.heap.page_allocator;
    const tree = TreeType.init(allocator, source);

    var ps = ParserState{
        .source = source,
        .pos = 0,
        .allocator = allocator,
        .tree = tree,
        .tok = undefined,
        .peek = undefined,
        .have_peek = false,
        .next_is_statement_start = true,
    };

    const root_id = parseProgram(&ps);

    if (root_id == maxU32) {
        tree.deinit();
        return null;
    }

    return tree;
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !?*TreeType {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const source = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(source);
    const source_z = try allocator.alloc(u8, source.len + 1);
    defer allocator.free(source_z);
    @memcpy(source_z[0..source.len], source);
    source_z[source.len] = 0;
    return parseString(source_z[0..source.len :0]);
}

pub fn getNodeText(node: NodeType, source: []const u8) []const u8 {
    if (node.isNull()) return "";
    const tree = node.tree.?;
    const data = tree.getData(node.id);
    return source[data.start_byte..data.end_byte];
}

pub fn getNodeName(node: NodeType) []const u8 {
    if (node.isNull()) return "";
    return node.tree.?.getNodeName(node);
}

pub fn childCount(node: NodeType) usize {
    return node.tree.?.childCount(node);
}

pub fn childAt(node: NodeType, index: usize) NodeType {
    return node.tree.?.childAt(node, @intCast(index));
}

pub fn namedChildCount(node: NodeType) usize {
    return node.tree.?.namedChildCount(node);
}

pub fn namedChild(node: NodeType, index: usize) NodeType {
    return node.tree.?.namedChild(node, @intCast(index));
}

pub fn childByFieldName(node: NodeType, field_name: [:0]const u8) ?NodeType {
    return node.tree.?.childByFieldName(node, field_name);
}

pub fn isNull(node: NodeType) bool {
    return node.isNull();
}

pub fn nextSibling(node: NodeType) NodeType {
    return node.tree.?.nextSibling(node);
}

pub fn prevSibling(node: NodeType) NodeType {
    return node.tree.?.prevSibling(node);
}

pub fn namedNextSibling(node: NodeType) NodeType {
    return node.tree.?.namedNextSibling(node);
}

pub fn namedPrevSibling(node: NodeType) NodeType {
    return node.tree.?.namedPrevSibling(node);
}

pub fn rootNode(tree: *const TreeType) NodeType {
    return tree.root();
}

pub fn treeDelete(tree: *TreeType) void {
    tree.deinit();
}

pub fn nodeHasError(node: NodeType) bool {
    _ = node;
    return false;
}

pub fn nodeStartByte(node: NodeType) usize {
    if (node.isNull()) return 0;
    return node.tree.?.getData(node.id).start_byte;
}

pub fn nodeEndByte(node: NodeType) usize {
    if (node.isNull()) return 0;
    return node.tree.?.getData(node.id).end_byte;
}

fn createBodyNode(ps: *ParserState, stmts: []const u32) u32 {
    if (stmts.len == 0) return maxU32;
    if (stmts.len == 1) return stmts[0];

    const start = ps.tree.getData(stmts[0]).start_byte;
    var end = ps.tree.getData(stmts[stmts.len - 1]).end_byte;

    const body_id = ps.tree.addNode("do_group", start, end, true, null);
    for (stmts) |s| {
        ps.tree.setChildLink(body_id, s);
        const s_end = ps.tree.getData(s).end_byte;
        if (s_end > end) end = s_end;
    }
    ps.tree.nodes.items[body_id].end_byte = end;
    return body_id;
}
