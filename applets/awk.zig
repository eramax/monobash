const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "awk", .main = main };
const Pattern = union(enum) { always, regex: []const u8, ncmp: struct { var_name: []const u8, op: []const u8, val: usize } };
const Action = union(enum) { print_all, print_field: usize, print_expr: []const u8 };
const Rule = struct { pattern: Pattern, action: Action };
pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "awk: usage: awk 'program' [file]\n", .{});
    const alloc = std.heap.page_allocator;
    const program = args[1];
    const file = if (args.len > 2) args[2] else "";
    const rules = parseProgram(program, alloc) catch return core.die(1, "awk: parse error\n", .{});
    defer alloc.free(rules);
    var fd: c_int = 0;
    if (file.len > 0) {
        var fbuf: [4096:0]u8 = undefined;
        if (file.len >= fbuf.len) return core.die(1, "awk: path too long\n", .{});
        @memcpy(fbuf[0..file.len], file);
        fbuf[file.len] = 0;
        fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "awk: cannot open '{s}'\n", .{file});
    }
    defer {
        if (file.len > 0 and fd > 0) _ = core.c.close(fd);
    }
    var reader = core.LineReader.init(fd);
    var nr: usize = 0;
    while (reader.next()) |line| {
        nr += 1;
        for (rules) |rule| {
            if (!matchPattern(rule.pattern, line, nr)) continue;
            execAction(rule.action, line);
        }
    }
    return 0;
}
fn parseProgram(prog: []const u8, alloc: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayListAligned(Rule, null).empty;
    var rest = std.mem.trim(u8, prog, " \t");
    while (rest.len > 0) {
        var pattern: Pattern = .always;
        var action_start: usize = 0;
        if (rest[0] == '/') {
            const end = std.mem.indexOfScalar(u8, rest[1..], '/') orelse return error.ParseError;
            pattern = .{ .regex = rest[1 .. 1 + end] };
            action_start = 2 + end + 1;
            while (action_start < rest.len and rest[action_start] == ' ') action_start += 1;
        } else if (rest[0] == '{') {
            action_start = 0;
        } else {
            return error.ParseError;
        }
        if (action_start < rest.len and rest[action_start] == '{') {
            const brace_end = findMatchingBrace(rest, action_start) orelse return error.ParseError;
            const action_body = std.mem.trim(u8, rest[action_start + 1 .. brace_end], " \t");
            const action = parseAction(action_body) orelse return error.ParseError;
            try rules.append(alloc, .{ .pattern = pattern, .action = action });
            rest = std.mem.trim(u8, rest[brace_end + 1 ..], " \t");
            if (rest.len > 0 and rest[0] == ';') rest = std.mem.trim(u8, rest[1..], " \t");
        } else {
            try rules.append(alloc, .{ .pattern = pattern, .action = Action{ .print_all = {} } });
            break;
        }
    }
    if (rules.items.len == 0) try rules.append(alloc, .{ .pattern = .always, .action = Action{ .print_all = {} } });
    return rules.toOwnedSlice(alloc);
}
fn findMatchingBrace(s: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < s.len) {
        if (s[i] == '{') depth += 1;
        if (s[i] == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
        i += 1;
    }
    return null;
}
fn parseAction(body: []const u8) ?Action {
    if (std.mem.startsWith(u8, body, "print")) {
        const rest = std.mem.trim(u8, body["print".len..], " \t");
        if (rest.len == 0) return Action{ .print_all = {} };
        if (std.mem.eql(u8, rest, "$0")) return Action{ .print_all = {} };
        if (rest.len > 0 and rest[0] == '$') {
            const n = std.fmt.parseInt(usize, rest[1..], 10) catch return null;
            return Action{ .print_field = n };
        }
        return Action{ .print_expr = rest };
    }
    return Action{ .print_all = {} };
}
fn matchPattern(p: Pattern, line: []const u8, _: usize) bool {
    switch (p) {
        .always => return true,
        .regex => |re| {
            for (line, 0..) |_, i| {
                if (i + re.len <= line.len and std.mem.eql(u8, line[i .. i + re.len], re)) return true;
            }
            return false;
        },
        .ncmp => return false,
    }
}
fn execAction(a: Action, line: []const u8) void {
    switch (a) {
        .print_all => {
            core.writeAll(1, line);
            core.writeAll(1, "\n");
        },
        .print_field => |f| {
            if (f == 0) {
                core.writeAll(1, line);
            } else {
                var idx: usize = 0;
                var field_no: usize = 0;
                while (idx < line.len) {
                    while (idx < line.len and line[idx] == ' ') idx += 1;
                    if (idx >= line.len) break;
                    field_no += 1;
                    const start = idx;
                    while (idx < line.len and line[idx] != ' ') idx += 1;
                    if (field_no == f) {
                        core.writeAll(1, line[start..idx]);
                        break;
                    }
                }
            }
            core.writeAll(1, "\n");
        },
        .print_expr => |expr| {
            core.writeAll(1, expr);
            core.writeAll(1, "\n");
        },
    }
}
