const std = @import("std");
const parser = @import("parser.zig");
const var_store = @import("var.zig");
const expand = @import("expand.zig");
const builtins = @import("builtins.zig");
const applets = @import("applets.zig");

const c = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("sys/wait.h");
});

const NodeType = parser.NodeType;

const ProgramMode = enum {
    interactive,
    script,
};

var mode: ProgramMode = .script;
var allocator: std.mem.Allocator = undefined;
var functions: std.StringHashMap(NodeType) = undefined;
var loop_depth: usize = 0;
var break_requested: bool = false;
var continue_requested: bool = false;
var return_requested: bool = false;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
    functions = std.StringHashMap(NodeType).init(alloc);
}

pub fn exec(io: std.Io, tree: *const parser.TreeType, src: []const u8) u8 {
    const node = parser.rootNode(tree);

    if (parser.nodeHasError(node)) {
        const msg = "monobash: syntax error near unexpected token\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 2;
    }

    const status = execNode(io, node, src);

    // Fire EXIT trap (only for top-level shell execution)
    fireExitTrap(io);

    return status;
}

fn fireExitTrap(io: std.Io) void {
    if (builtins.getTrap("EXIT")) |cmd| {
        if (cmd.len == 0) return;
        const cmd_z = allocator.dupeZ(u8, cmd) catch return;
        defer allocator.free(cmd_z);
        if (parser.parseString(cmd_z)) |trap_tree| {
            defer parser.treeDelete(trap_tree);
            _ = execNode(io, parser.rootNode(trap_tree), cmd);
        }
    }
}

fn nodeText(node: NodeType, source: []const u8) []const u8 {
    return parser.getNodeText(node, source);
}

fn nodeName(node: NodeType) []const u8 {
    return parser.getNodeName(node);
}

fn execNode(io: std.Io, node: NodeType, source: []const u8) u8 {
    const status = execNodeInner(io, node, source);
    recordExitStatus(status);
    return status;
}

fn execNodeInner(io: std.Io, node: NodeType, source: []const u8) u8 {
    const name = nodeName(node);

    // Dispatch by node type
    if (std.mem.eql(u8, name, "program")) {
        return execProgram(io, node, source);
    }
    if (std.mem.eql(u8, name, "command")) {
        return execCommand(io, node, source);
    }
    if (std.mem.eql(u8, name, "simple_command")) {
        return execSimpleCommand(io, node, source);
    }
    if (std.mem.eql(u8, name, "list")) {
        return execList(io, node, source);
    }
    if (std.mem.eql(u8, name, "if_statement")) {
        return execIf(io, node, source);
    }
    if (std.mem.eql(u8, name, "for_statement")) {
        return execFor(io, node, source);
    }
    if (std.mem.eql(u8, name, "c_style_for_statement")) {
        return execCStyleFor(io, node, source);
    }
    if (std.mem.eql(u8, name, "while_statement")) {
        return execWhile(io, node, source);
    }
    if (std.mem.eql(u8, name, "pipeline")) {
        return execPipeline(io, node, source);
    }
    if (std.mem.eql(u8, name, "redirected_statement")) {
        return execRedirected(io, node, source);
    }
    if (std.mem.eql(u8, name, "compound_statement")) {
        return execCompound(io, node, source);
    }
    if (std.mem.eql(u8, name, "subshell")) {
        return execSubshell(io, node, source);
    }
    if (std.mem.eql(u8, name, "negated_command")) {
        return execNegated(io, node, source);
    }
    if (std.mem.eql(u8, name, "test_command")) {
        return execTest(io, node, source);
    }
    if (std.mem.eql(u8, name, "declaration_command")) {
        return execDeclaration(io, node, source);
    }
    if (std.mem.eql(u8, name, "variable_assignment")) {
        return execVarAssign(io, node, source);
    }
    if (std.mem.eql(u8, name, "case_statement")) {
        return execCase(io, node, source);
    }
    if (std.mem.eql(u8, name, "function_definition")) {
        return execFnDef(io, node, source);
    }
    if (std.mem.eql(u8, name, "unset_command")) {
        return execUnset(io, node, source);
    }
    if (std.mem.eql(u8, name, "export_command")) {
        return execExport(io, node, source);
    }
    if (std.mem.eql(u8, name, "do_group")) {
        return execCompound(io, node, source);
    }

    return 0;
}

fn recordExitStatus(status: u8) void {
    var_store.setExitStatus(status);
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{status}) catch "0";
    var_store.set("?", s, false);
}

fn execProgram(io: std.Io, node: NodeType, source: []const u8) u8 {
    var last: u8 = 0;
    const count = parser.childCount(node);
    var i: usize = 0;
    var prev_was_semi = false;
    while (i < count) {
        const child = parser.childAt(node, i);
        const cname = nodeName(child);

        // Check if next child is &
        var is_background = false;
        if (i + 1 < count) {
            const next = parser.childAt(node, i + 1);
            if (std.mem.eql(u8, nodeName(next), "&")) {
                is_background = true;
            }
        }

        if (is_background) {
            prev_was_semi = false;
            const pid = c.fork();
            if (pid < 0) return 1;
            if (pid == 0) {
                c._exit(execNode(io, child, source));
            }
            var_store.addJob(@intCast(pid));
            var_store.setLastBgPid(@intCast(pid));
            var buf: [16]u8 = undefined;
            const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch "0";
            var_store.set("!", pid_str, false);
            i += 2;
        } else {
            if (isSyntaxErrorToken(cname)) {
                const msg = "monobash: syntax error near unexpected token `;;'\n";
                _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
                return 2;
            }
            if (isTerminator(cname)) {
                if (prev_was_semi and std.mem.eql(u8, cname, ";")) {
                    const msg = "monobash: syntax error near unexpected token `;;'\n";
                    _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
                    return 2;
                }
                prev_was_semi = std.mem.eql(u8, cname, ";");
                i += 1;
                continue;
            }
            prev_was_semi = false;
            const status = execNode(io, child, source);
            last = status;
            recordExitStatus(status);
            if (var_store.errexit and status != 0) {
                return status;
            }
            i += 1;
        }
    }
    return last;
}

fn isTerminator(name: []const u8) bool {
    return std.mem.eql(u8, name, ";") or
        std.mem.eql(u8, name, "&") or
        std.mem.eql(u8, name, "|");
}

fn isSyntaxErrorToken(name: []const u8) bool {
    return std.mem.eql(u8, name, ";;");
}

fn execList(io: std.Io, node: NodeType, source: []const u8) u8 {
    var last: u8 = 0;
    const count = parser.childCount(node);
    var i: usize = 0;
    while (i < count) {
        const child = parser.childAt(node, i);

        // Check what operator follows this child
        if (i + 1 < count) {
            const next = parser.childAt(node, i + 1);
            const next_name = nodeName(next);
            if (std.mem.eql(u8, next_name, "&&")) {
                const status = execNode(io, child, source);
                last = status;
                if (status != 0) break; // short-circuit: && fails
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, next_name, "||")) {
                const status = execNode(io, child, source);
                last = status;
                if (status == 0) break; // short-circuit: || succeeds
                i += 2;
                continue;
            }
        }

        const status = execNode(io, child, source);
        last = status;
        if (var_store.errexit and status != 0) {
            return status;
        }
        i += 1;
    }
    return last;
}

fn execCommand(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.childCount(node);

    // Check if first child is simple_command or has command_name/word children
    if (count > 0) {
        const first = parser.childAt(node, 0);
        const firstName = nodeName(first);
        if (std.mem.eql(u8, firstName, "simple_command")) {
            return execSimpleCommand(io, first, source);
        }
        if (std.mem.eql(u8, firstName, "command_name") or std.mem.eql(u8, firstName, "word")) {
            return execSimpleCommand(io, node, source);
        }
    }

    // Redirected, compound, if, for, etc. — recurse into children
    var last: u8 = 0;
    for (0..count) |i| {
        const child = parser.childAt(node, i);
        last = execNode(io, child, source);
    }
    return last;
}

fn execSimpleCommand(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.childCount(node);
    var expanded: std.ArrayListAligned([]const u8, null) = .empty;
    defer expanded.deinit(allocator);

    // First, process variable assignments
    for (0..count) |i| {
        const child = parser.childAt(node, i);
        if (std.mem.eql(u8, nodeName(child), "variable_assignment")) {
            _ = execVarAssign(io, child, source);
        }
    }

    var i: usize = 0;
    while (i < count) {
        const child = parser.childAt(node, i);
        const cname = nodeName(child);
        var is_skip = false;
        inline for (.{ "redirected_statement", "heredoc_body", "file_redirect",
            "file_descriptor", "herestring_redirect", "heredoc_redirect", "heredoc_start", "variable_assignment" }) |st| {
            if (std.mem.eql(u8, cname, st)) {
                is_skip = true;
            }
        }
        if (is_skip) {
            i += 1;
            continue;
        }

        var raw = nodeText(child, source);

        // Detect backslash-newline continuation between word/string nodes.
        // tree-sitter-bash's lexer handles \<newline> by consuming the backslash
        // and newline without including them in the token, but the surrounding
        // text becomes separate word tokens. We merge them back here.
        {
            var next_i = i + 1;
            while (next_i < count) {
                const next_child = parser.childAt(node, next_i);
                const next_name = nodeName(next_child);

                var next_is_skip = false;
                inline for (.{ "redirected_statement", "heredoc_body", "file_redirect",
                    "file_descriptor", "herestring_redirect", "heredoc_redirect", "heredoc_start", "variable_assignment" }) |st| {
                    if (std.mem.eql(u8, next_name, st)) {
                        next_is_skip = true;
                    }
                }
                if (next_is_skip) {
                    next_i += 1;
                    continue;
                }

                if (std.mem.eql(u8, next_name, "word") or std.mem.eql(u8, next_name, "string")) {
                    const end_byte = parser.nodeEndByte(child);
                    const next_start = parser.nodeStartByte(next_child);
                    if (next_start > end_byte) {
                        const gap = source[end_byte..next_start];
                        if (std.mem.indexOf(u8, gap, "\\\n") != null or std.mem.indexOf(u8, gap, "\\\r\n") != null) {
                            const next_raw = nodeText(next_child, source);
                            raw = std.mem.concat(allocator, u8, &.{ raw, next_raw }) catch raw;
                            i = next_i;
                            break;
                        }
                    }
                    break;
                }
                break;
            }
        }

        if (expand.expandToken(allocator, raw)) |result| {
            var list = result;
            defer list.deinit();
            for (list.words) |w| {
                const dup = allocator.dupe(u8, w) catch @panic("oom");
                expanded.append(allocator, dup) catch @panic("oom");
            }
        } else |err| {
            if (err == error.UndefinedVar) {
                return 127;
            }
            i += 1;
            continue;
        }
        i += 1;
    }

    if (expanded.items.len == 0) return 0;

    const cmd_name = expanded.items[0];

    // Check if it's a function
    if (functions.get(cmd_name)) |fn_node| {
        const ncount = parser.namedChildCount(fn_node);
        if (ncount >= 2) {
            // Save old positional params
            const old_params = var_store.getPositional();

            // Set new positional params from function arguments
            if (expanded.items.len > 1) {
                var_store.setPositional(allocator, expanded.items[1..]);
            } else {
                var_store.setPositional(allocator, &.{});
            }

            // Execute function body
            const body = parser.namedChild(fn_node, 1);
            const result = execNode(io, body, source);

            // Restore positional params
            var_store.setPositional(allocator, old_params.items);

            return result;
        }
        return 1;
    }

    // Special builtins that need executor context
    if (std.mem.eql(u8, cmd_name, "eval")) {
        return execBuiltinEval(io, source, expanded.items);
    }
    if (std.mem.eql(u8, cmd_name, "source") or std.mem.eql(u8, cmd_name, ".")) {
        return execBuiltinSource(io, expanded.items);
    }
    if (std.mem.eql(u8, cmd_name, "exec")) {
        return execBuiltinExec(io, expanded.items);
    }
    if (std.mem.eql(u8, cmd_name, "break")) {
        if (loop_depth > 0) break_requested = true;
        return 0;
    }
    if (std.mem.eql(u8, cmd_name, "continue")) {
        if (loop_depth > 0) continue_requested = true;
        return 0;
    }
    if (std.mem.eql(u8, cmd_name, "return")) {
        return_requested = true;
        if (expanded.items.len > 1) {
            const val = std.fmt.parseInt(u8, expanded.items[1], 10) catch 0;
            recordExitStatus(val);
        } else {
            recordExitStatus(0);
        }
        return 0;
    }

    // Check builtins first
    if (builtins.lookup(cmd_name)) |_| {
        return builtins.run(io, cmd_name, expanded.items);
    }

    // Check applets (NOEXEC)
    if (applets.lookup(cmd_name)) |_| {
        return applets.run(io, cmd_name, expanded.items);
    }

    // Try external command via fork+execvp
    return execExternal(cmd_name, expanded.items);
}

fn execExternal(cmd: []const u8, args: [][]const u8) u8 {
    const pid = c.fork();
    if (pid < 0) return 126;

    if (pid == 0) {
        // Build C-style argv
        const argv = allocator.alloc([*c]u8, args.len + 1) catch @panic("oom");
        defer allocator.free(argv);
        for (args, 0..) |arg, i| {
            const arg_z = allocator.dupeZ(u8, arg) catch @panic("oom");
            argv[i] = arg_z.ptr;
        }
        argv[args.len] = null;

        const cmd_z = allocator.dupeZ(u8, cmd) catch @panic("oom");
        _ = c.execvp(cmd_z.ptr, argv.ptr);

        // If execvp returns, it failed
        c._exit(127);
    }

    // Parent: wait for child
    var wstatus: c_int = 0;
    _ = c.waitpid(pid, &wstatus, 0);
    const result = if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
        @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))))
    else
        1;
    recordExitStatus(result);
    return result;
}

fn execIf(io: std.Io, node: NodeType, source: []const u8) u8 {
    const ncount = parser.namedChildCount(node);
    if (ncount == 0) return 0;

    var idx: usize = 0;
    while (idx < ncount) {
        const child = parser.namedChild(node, @intCast(idx));
        const cname = nodeName(child);

        if (std.mem.eql(u8, cname, "elif_clause")) {
            // Treat elif as an inline if: condition is first named child, body is second
            const enc = parser.namedChildCount(child);
            if (enc >= 2) {
                const econd = parser.namedChild(child, 0);
                const estatus = execNode(io, econd, source);
                if (estatus == 0) {
                    const ebody = parser.namedChild(child, 1);
                    return execNode(io, ebody, source);
                }
                // elif condition false: check if it has an else (third named child)
                if (enc >= 3) {
                    const eelse = parser.namedChild(child, 2);
                    const eelse_name = nodeName(eelse);
                    if (std.mem.eql(u8, eelse_name, "else_clause")) {
                        const eelse_c = parser.namedChildCount(eelse);
                        if (eelse_c > 0) {
                            return execNode(io, parser.namedChild(eelse, 0), source);
                        }
                    }
                }
                // elif condition false, no else taken — continue to next child
            }
        } else if (std.mem.eql(u8, cname, "else_clause")) {
            const ecount = parser.namedChildCount(child);
            if (ecount > 0) {
                return execNode(io, parser.namedChild(child, 0), source);
            }
        } else if (idx == 0) {
            // First named child = condition
            const status = execNode(io, child, source);
            if (status == 0 and ncount > 1) {
                const body = parser.namedChild(node, 1);
                return execNode(io, body, source);
            }
        }
        idx += 1;
    }
    return 0;
}

fn detectSelect(node: NodeType, source: []const u8) bool {
    const count = parser.childCount(node);
    if (count == 0) return false;
    const first = parser.childAt(node, 0);
    const first_txt = nodeText(first, source);
    return std.mem.eql(u8, first_txt, "select");
}

fn execFor(io: std.Io, node: NodeType, source: []const u8) u8 {
    const ncount = parser.namedChildCount(node);
    if (ncount == 0) return 0;

    // Detect if this is a "select" loop (first unnamed child is "select" keyword)
    const is_select = detectSelect(node, source);

    const first = parser.namedChild(node, 0);
    const var_name = nodeText(first, source);

    // Collect word arguments (named children between var and body)
    var words: std.ArrayListAligned([]const u8, null) = .empty;
    defer words.deinit(allocator);

    // Find body - the last named child that is a command or do_group
    var body_idx: usize = ncount; // default to last index
    var found_body = false;
    for (1..ncount) |i| {
        const child = parser.namedChild(node, @intCast(i));
        const cname = nodeName(child);
        if (std.mem.eql(u8, cname, "command") or std.mem.eql(u8, cname, "simple_command") or
            std.mem.eql(u8, cname, "compound_statement") or std.mem.eql(u8, cname, "redirected_statement") or
            std.mem.eql(u8, cname, "do_group") or std.mem.eql(u8, cname, "function_definition") or
            std.mem.eql(u8, cname, "if_statement") or std.mem.eql(u8, cname, "for_statement") or
            std.mem.eql(u8, cname, "while_statement") or std.mem.eql(u8, cname, "case_statement"))
        {
            body_idx = i;
            found_body = true;
        }
    }

    // If no body found, nothing to iterate
    if (!found_body) return 0;

    // Words are all named children between index 1 and body_idx that are word/string nodes
    if (body_idx > 1) {
        for (1..body_idx) |i| {
            const child = parser.namedChild(node, @intCast(i));
            const raw = nodeText(child, source);
            const exp_result = expand.expandToken(allocator, raw) catch { continue; };
            var list = exp_result;
            defer list.deinit();
            for (list.words) |w| {
                const dup = allocator.dupe(u8, w) catch @panic("oom");
                words.append(allocator, dup) catch @panic("oom");
            }
        }
    }

    // If no explicit word list, use "$@" (positional params)
    if (words.items.len == 0) {
        const positional = var_store.getPositional();
        for (positional.items) |p| {
            words.append(allocator, p) catch @panic("oom");
        }
    }

    const body = parser.namedChild(node, @intCast(body_idx));

    loop_depth += 1;
    defer loop_depth -= 1;

    var last_status: u8 = 0;
    if (is_select) {
        // Basic select: present menu and iterate
        const stdout = std.Io.File.stdout();
        for (words.items, 0..) |w, idx| {
            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{d}) {s}\n", .{idx + 1, w}) catch continue;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
        }
        // Use first word by default (no interactive input in non-interactive mode)
        if (words.items.len > 0) {
            var_store.setLocal(var_name, words.items[0], false);
            last_status = execNode(io, body, source);
        }
    } else {
        for (words.items) |w| {
            if (break_requested) {
                break_requested = false;
                break;
            }
            if (continue_requested) {
                continue_requested = false;
                continue;
            }
            var_store.setLocal(var_name, w, false);
            last_status = execNode(io, body, source);
        }
    }

    return last_status;
}

fn evalArithmetic(alloc: std.mem.Allocator, expr_text: []const u8) ?i64 {
    if (expr_text.len == 0) return null;
    return expand.evalArithmeticFromStr(alloc, expr_text) catch null;
}

fn execCStyleFor(io: std.Io, node: NodeType, source: []const u8) u8 {
    // Fields: initializer, condition, update, body
    const init_node = parser.childByFieldName(node, "initializer");
    const cond_node = parser.childByFieldName(node, "condition");
    const update_node = parser.childByFieldName(node, "update");
    const body_node = parser.childByFieldName(node, "body") orelse return 0;

    // Evaluate initializer
    if (init_node) |n| {
        const text = nodeText(n, source);
        if (std.mem.indexOfScalar(u8, text, '=')) |eq| {
            const vname = text[0..eq];
            const vval = text[eq + 1 ..];
            var_store.setLocal(vname, vval, false);
        } else {
            _ = evalArithmetic(allocator, text);
        }
    }

    loop_depth += 1;
    defer loop_depth -= 1;

    var last_status: u8 = 0;
    var iter_count: u32 = 0;
    while (iter_count < 1000000) : (iter_count += 1) {
        if (break_requested) {
            break_requested = false;
            break;
        }
        if (continue_requested) {
            continue_requested = false;
        }

        if (cond_node) |n| {
            const cond_text = nodeText(n, source);
            const cond_val = evalArithmetic(allocator, cond_text) orelse 1;
            if (cond_val == 0) break;
        }

        last_status = execNode(io, body_node, source);

        if (update_node) |n| {
            const upd_text = nodeText(n, source);
            _ = evalArithmetic(allocator, upd_text);
        }
    }

    return last_status;
}

fn execWhile(io: std.Io, node: NodeType, source: []const u8) u8 {
    const ncount = parser.namedChildCount(node);
    if (ncount < 2) return 0;

    // First named child is the condition command
    const condition = parser.namedChild(node, 0);
    // Second named child is the body (do/done body)
    const body = parser.namedChild(node, 1);

    // Check if it's 'until' by looking at unnamed children
    const total = parser.childCount(node);
    var is_until = false;
    for (0..total) |i| {
        const child = parser.childAt(node, @intCast(i));
        const cname = nodeName(child);
        if (std.mem.eql(u8, cname, "until")) {  // 'until' keyword is an unnamed child maybe
            is_until = true;
        }
    }

    loop_depth += 1;
    defer loop_depth -= 1;

    var last_status: u8 = 0;
    var iter_count: u32 = 0;
    while (iter_count < 1000000) : (iter_count += 1) {
        if (break_requested) {
            break_requested = false;
            break;
        }
        if (continue_requested) {
            continue_requested = false;
        }

        const cond_status = execNode(io, condition, source);
        const cond_true = (cond_status == 0);

        if (is_until) {
            if (cond_true) break;
        } else {
            if (!cond_true) break;
        }

        last_status = execNode(io, body, source);
    }

    return last_status;
}

fn execPipeline(io: std.Io, node: NodeType, source: []const u8) u8 {
    // Collect all command children (skip | tokens)
    var commands: std.ArrayListAligned(NodeType, null) = .empty;
    defer commands.deinit(allocator);
    const total = parser.childCount(node);
    for (0..total) |i| {
        const child = parser.childAt(node, @intCast(i));
        const cname = nodeName(child);
        // Only include command nodes, skip pipes
        if (std.mem.eql(u8, cname, "command") or
            std.mem.eql(u8, cname, "simple_command") or
            std.mem.eql(u8, cname, "redirected_statement") or
            std.mem.eql(u8, cname, "subshell") or
            std.mem.eql(u8, cname, "compound_statement") or
            std.mem.eql(u8, cname, "if_statement") or
            std.mem.eql(u8, cname, "for_statement") or
            std.mem.eql(u8, cname, "while_statement") or
            std.mem.eql(u8, cname, "case_statement") or
            std.mem.eql(u8, cname, "function_definition") or
            std.mem.eql(u8, cname, "declaration_command") or
            std.mem.eql(u8, cname, "test_command"))
        {
            commands.append(allocator, child) catch @panic("oom");
        }
    }

    const ncommands = commands.items.len;
    if (ncommands == 0) return 0;
    if (ncommands == 1) return execNode(io, commands.items[0], source);

    // Create pipes: N-1 pipes for N commands
    var pipe_fds: std.ArrayListAligned([2]c_int, null) = .empty;
    defer pipe_fds.deinit(allocator);
    for (0..ncommands - 1) |_| {
        var fds: [2]c_int = undefined;
        if (c.pipe(&fds) != 0) return 1;
        pipe_fds.append(allocator, fds) catch @panic("oom");
    }

    // Fork for each command
    var pids: std.ArrayListAligned(c_int, null) = .empty;
    defer pids.deinit(allocator);
    var last_status: u8 = 0;

    for (0..ncommands) |cmd_idx| {
        const pid = c.fork();
        if (pid < 0) {
            // Fork failed — close pipes and return
            for (pipe_fds.items) |pfds| {
                _ = c.close(pfds[0]);
                _ = c.close(pfds[1]);
            }
            return 1;
        }
        if (pid == 0) {
            // Child process
            // Set up stdin from previous pipe (if not first)
            if (cmd_idx > 0) {
                const prev = pipe_fds.items[cmd_idx - 1];
                _ = c.dup2(prev[0], 0); // stdin
            }
            // Set up stdout to next pipe (if not last)
            if (cmd_idx < ncommands - 1) {
                const next = pipe_fds.items[cmd_idx];
                _ = c.dup2(next[1], 1); // stdout
            }
            // Close all pipe fds in child
            for (pipe_fds.items) |pfds| {
                _ = c.close(pfds[0]);
                _ = c.close(pfds[1]);
            }
            // Execute the command
            const status = execNode(io, commands.items[cmd_idx], source);
            c._exit(status);
        }
        pids.append(allocator, pid) catch @panic("oom");
    }

    // Close all pipe fds in parent
    for (pipe_fds.items) |pfds| {
        _ = c.close(pfds[0]);
        _ = c.close(pfds[1]);
    }

    // Wait for all children and collect statuses
    var statuses: std.ArrayListAligned(u8, null) = .empty;
    defer statuses.deinit(allocator);
    statuses.resize(allocator, pids.items.len) catch @panic("oom");

    for (pids.items, 0..) |pid, i| {
        var wstatus: c_int = 0;
        _ = c.waitpid(pid, &wstatus, 0);
        const stat = if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
            @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))))
        else
            1;
        statuses.items[i] = stat;
        if (i == pids.items.len - 1) {
            last_status = stat;
        }
    }

    const result = if (var_store.pipefail) blk: {
        var r: u8 = 0;
        for (statuses.items) |s| {
            if (s != 0) r = s;
        }
        break :blk r;
    } else last_status;
    recordExitStatus(result);
    return result;
}

const Redirect = struct { op: []const u8, target: []const u8 };

fn execRedirected(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.childCount(node);
    if (count == 0) return 0;

    // First child is the command
    const cmd = parser.childAt(node, 0);

    // Collect redirects
    var redirects: std.ArrayListAligned(Redirect, null) = .empty;
    defer redirects.deinit(allocator);

    // Handle heredoc/herestring: create a pipe for stdin content
    var heredoc_pipe: [2]c_int = .{ -1, -1 };
    var heredoc_body_text: ?[]const u8 = null;
    var is_herestring: bool = false;

    for (1..count) |i| {
        const child = parser.childAt(node, @intCast(i));
        const cname = nodeName(child);
        if (std.mem.eql(u8, cname, "file_redirect")) {
            const redirect = parseFileRedirect(child, source);
            if (redirect) |r| {
                redirects.append(allocator, r) catch @panic("oom");
            }
        } else if (std.mem.eql(u8, cname, "heredoc_redirect")) {
            // Extract heredoc body
            const hcount = parser.childCount(child);
            for (0..hcount) |j| {
                const hc = parser.childAt(child, @intCast(j));
                const hcname = nodeName(hc);
                if (std.mem.eql(u8, hcname, "heredoc_body")) {
                    heredoc_body_text = nodeText(hc, source);
                    // Also record that we need to redirect stdin
                    redirects.append(allocator, .{ .op = "<<", .target = "" }) catch @panic("oom");
                }
            }
        } else if (std.mem.eql(u8, cname, "herestring_redirect")) {
            is_herestring = true;
            // Extract word from herestring
            const hcount = parser.childCount(child);
            for (0..hcount) |j| {
                const hc = parser.childAt(child, @intCast(j));
                const hcname = nodeName(hc);
                if (std.mem.eql(u8, hcname, "word") or std.mem.eql(u8, hcname, "string") or
                    std.mem.eql(u8, hcname, "simple_expansion") or std.mem.eql(u8, hcname, "expansion")) {
                    const raw = nodeText(hc, source);
                    var exp_result = expand.expandToken(allocator, raw) catch continue;
                    defer exp_result.deinit();
                    if (exp_result.words.len > 0) {
                        heredoc_body_text = allocator.dupe(u8, exp_result.words[0]) catch continue;
                    } else {
                        heredoc_body_text = "";
                    }
                    redirects.append(allocator, .{ .op = "<<", .target = "" }) catch @panic("oom");
                }
            }
        }
    }

    const use_pipe = heredoc_body_text != null;

    // If no redirects, just execute directly
    if (redirects.items.len == 0) return execNode(io, cmd, source);

    // Create pipe for heredoc/herestring content
    if (use_pipe) {
        if (c.pipe(&heredoc_pipe) != 0) return 1;
    }

    // Fork to apply redirects in the child
    const pid = c.fork();
    if (pid < 0) {
        if (use_pipe) { _ = c.close(heredoc_pipe[0]); _ = c.close(heredoc_pipe[1]); }
        return 1;
    }

    if (pid == 0) {
        // Child: apply redirects
        if (use_pipe) {
            // Redirect stdin from the pipe read end
            _ = c.dup2(heredoc_pipe[0], 0);
            _ = c.close(heredoc_pipe[0]);
            _ = c.close(heredoc_pipe[1]);
        }
        if (applyRedirects(redirects.items) != 0) {
            c._exit(1);
        }
        const status = execNode(io, cmd, source);
        c._exit(status);
    }

    // Parent: if heredoc/herestring, write content to pipe
    if (use_pipe) {
        _ = c.close(heredoc_pipe[0]);
        if (heredoc_body_text) |content| {
            if (content.len > 0) {
                _ = c.write(heredoc_pipe[1], content.ptr, @intCast(content.len));
            }
            // Bash adds newline after herestring content
            if (is_herestring) {
                _ = c.write(heredoc_pipe[1], "\n", 1);
            }
        } else {
            // Empty herestring: still write the newline
            if (is_herestring) {
                _ = c.write(heredoc_pipe[1], "\n", 1);
            }
        }
        _ = c.close(heredoc_pipe[1]);
    }

    // Parent: wait for child
    var wstatus: c_int = 0;
    _ = c.waitpid(pid, &wstatus, 0);
    const result = if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
        @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))))
    else
        1;
    recordExitStatus(result);
    return result;
}

fn parseFileRedirect(node: NodeType, source: []const u8) ?Redirect {
    const total = parser.childCount(node);
    if (total < 2) return null;

    var op_text: ?[]const u8 = null;
    var target_text: ?[]const u8 = null;
    var source_fd: ?[]const u8 = null;

    for (0..total) |i| {
        const child = parser.childAt(node, @intCast(i));
        const cname = nodeName(child);
        const text = nodeText(child, source);

        if (std.mem.eql(u8, cname, "file_descriptor")) {
            source_fd = text;
        } else if (std.mem.eql(u8, cname, "word") or std.mem.eql(u8, cname, "string")) {
            target_text = text;
        } else if (cname.len == 0) {
            // unnamed token = operator
            op_text = text;
        }
    }

    const target = target_text orelse return null;
    const op = op_text orelse return null;

    // If source fd exists (e.g., "2" for "2>&1"), prepend it to op
    if (source_fd) |fd| {
        var buf: [32]u8 = undefined;
        const combined = std.fmt.bufPrint(&buf, "{s}{s}", .{ fd, op }) catch {
            return .{ .op = op, .target = target };
        };
        const dup = allocator.dupe(u8, combined) catch {
            return .{ .op = op, .target = target };
        };
        return .{ .op = dup, .target = target };
    }

    return .{ .op = op, .target = target };
}

fn applyRedirects(redirects: []const Redirect) u8 {
    for (redirects) |r| {
        const target_z = allocator.dupeZ(u8, r.target) catch return 1;
        defer allocator.free(target_z);
        if (std.mem.eql(u8, r.op, ">")) {
            const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) return 1;
            _ = c.dup2(fd, 1);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, ">>")) {
            const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c_uint, 0o644));
            if (fd < 0) return 1;
            _ = c.dup2(fd, 1);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, "<")) {
            const fd = c.open(target_z.ptr, c.O_RDONLY);
            if (fd < 0) return 1;
            _ = c.dup2(fd, 0);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, "2>")) {
            const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) return 1;
            _ = c.dup2(fd, 2);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, "2>>")) {
            const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c_uint, 0o644));
            if (fd < 0) return 1;
            _ = c.dup2(fd, 2);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, "&>")) {
            // &> always redirects both stdout and stderr to a file (never fd-to-fd)
            const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) return 1;
            _ = c.dup2(fd, 1);
            _ = c.dup2(fd, 2);
            _ = c.close(fd);
        } else if (std.mem.eql(u8, r.op, ">&")) {
            // Try numeric target: fd-to-fd redirect (>&2 redirects stdout to stderr)
            // Non-numeric target: redirect both stdout and stderr to file
            const target_fd = std.fmt.parseInt(c_int, r.target, 10);
            if (target_fd) |fd| {
                if (fd != 1) _ = c.dup2(fd, 1);
            } else |_| {
                const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
                if (fd < 0) return 1;
                _ = c.dup2(fd, 1);
                _ = c.dup2(fd, 2);
                _ = c.close(fd);
            }
        } else if (std.mem.endsWith(u8, r.op, ">&")) {
            // Pattern: "N>&" where N is the source fd, target is the destination fd (or filename)
            // e.g., "2>&" with target "1" means dup2(1, 2) (stderr to stdout)
            const prefix = r.op[0 .. r.op.len - 2];
            const source_fd = if (prefix.len > 0)
                std.fmt.parseInt(c_int, prefix, 10) catch 1
            else
                1;
            const target_fd = std.fmt.parseInt(c_int, r.target, 10);
            if (target_fd) |fd| {
                _ = c.dup2(fd, source_fd);
            } else |_| {
                // Treat target as filename
                const fd = c.open(target_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
                if (fd < 0) return 1;
                _ = c.dup2(fd, source_fd);
                _ = c.close(fd);
            }
        }
    }
    return 0;
}

fn execCompound(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.childCount(node);
    // Check for (( ... )) arithmetic command
    if (count >= 2) {
        const first = parser.childAt(node, 0);
        const first_txt = nodeText(first, source);
        if (std.mem.startsWith(u8, first_txt, "((")) {
            return execArithmeticCmd(io, node, source);
        }
    }
    var last: u8 = 0;
    var i: usize = 0;
    while (i < count) {
        const child = parser.childAt(node, i);
        const cname = nodeName(child);

        // Check if next child is &
        var is_background = false;
        if (i + 1 < count) {
            const next = parser.childAt(node, i + 1);
            if (std.mem.eql(u8, nodeName(next), "&")) {
                is_background = true;
            }
        }

        if (is_background) {
            const pid = c.fork();
            if (pid < 0) return 1;
            if (pid == 0) {
                c._exit(execNode(io, child, source));
            }
            var_store.addJob(@intCast(pid));
            var_store.setLastBgPid(@intCast(pid));
            var buf: [16]u8 = undefined;
            const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch "0";
            var_store.set("!", pid_str, false);
            i += 2;
        } else {
            if (isSyntaxErrorToken(cname)) {
                const msg = "monobash: syntax error near unexpected token `;;'\n";
                _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
                return 2;
            }
            if (isTerminator(cname)) {
                i += 1;
                continue;
            }
            last = execNode(io, child, source);
            i += 1;
        }
    }
    return last;
}

fn execArithmeticCmd(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    const count = parser.childCount(node);
    // Collect text from unnamed children between (( and ))
    var expr_buf: [4096]u8 = undefined;
    var pos: usize = 0;
    for (0..count) |i| {
        const child = parser.childAt(node, i);
        const cname = nodeName(child);
        // Skip the (( and )) tokens
        if (std.mem.eql(u8, cname, "((") or std.mem.eql(u8, cname, "))")) continue;
        const text = nodeText(child, source);
        if (pos + text.len + 1 <= expr_buf.len) {
            if (pos > 0) { expr_buf[pos] = ' '; pos += 1; }
            @memcpy(expr_buf[pos..][0..text.len], text);
            pos += text.len;
        }
    }
    const expr_text = expr_buf[0..pos];
    if (expr_text.len == 0) return 0;
    const trimmed = std.mem.trim(u8, expr_text, " ");

    // Check for variable assignment: name = expression
    if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
        if (eq > 0 and trimmed[eq-1] != '=' and trimmed[eq-1] != '!' and
            trimmed[eq-1] != '<' and trimmed[eq-1] != '>' and
            trimmed[eq-1] != '+' and trimmed[eq-1] != '-' and
            trimmed[eq-1] != '*' and trimmed[eq-1] != '/' and trimmed[eq-1] != '%')
        {
            const name = std.mem.trim(u8, trimmed[0..eq], " ");
            const val_expr = std.mem.trim(u8, trimmed[eq+1..], " ");
            if (name.len > 0 and val_expr.len > 0) {
                if (evalArithmetic(allocator, val_expr)) |val| {
                    var vbuf: [32]u8 = undefined;
                    const val_str = std.fmt.bufPrint(&vbuf, "{d}", .{val}) catch "0";
                    var_store.set(name, val_str, false);
                    const is_zero = (val == 0);
                    const exit_val: u8 = if (is_zero) 1 else 0;
                    var qbuf: [16]u8 = undefined;
                    const s = std.fmt.bufPrint(&qbuf, "{d}", .{exit_val}) catch "0";
                    var_store.set("?", s, false);
                    return exit_val;
                }
                return 1;
            }
        }
    }

    const val = evalArithmetic(allocator, trimmed) orelse return 1;
    const is_zero = (val == 0);
    const exit_val: u8 = if (is_zero) 1 else 0;
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{exit_val}) catch "0";
    var_store.set("?", s, false);
    return exit_val;
}

fn execSubshell(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.childCount(node);
    if (count == 0) return 0;

    const pid = c.fork();
    if (pid < 0) return 1;

    if (pid == 0) {
        // Update subshell variables
        if (var_store.get("BASH_SUBSHELL")) |v| {
            const val = std.fmt.parseInt(u32, v.value, 10) catch 0;
            var buf: [16]u8 = undefined;
            const new_val = std.fmt.bufPrint(&buf, "{d}", .{val + 1}) catch "1";
            var_store.set("BASH_SUBSHELL", new_val, false);
        }
        {
            var buf: [16]u8 = undefined;
            const pid_str = std.fmt.bufPrint(&buf, "{d}", .{c_getpid()}) catch "0";
            var_store.set("BASHPID", pid_str, false);
        }

        // Child: execute the body
        var last_status: u8 = 0;
        for (0..count) |i| {
            const child = parser.childAt(node, @intCast(i));
            last_status = execNode(io, child, source);
        }
        c._exit(last_status);
    }

    // Parent: wait for child
    var wstatus: c_int = 0;
    _ = c.waitpid(pid, &wstatus, 0);
    const result = if (c.WIFEXITED(@as(c_int, @intCast(wstatus))))
        @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))))
    else
        1;
    recordExitStatus(result);
    return result;
}

extern "c" fn getpid() c_int;
fn c_getpid() c_int {
    return getpid();
}

fn execNegated(io: std.Io, node: NodeType, source: []const u8) u8 {
    const count = parser.namedChildCount(node);
    if (count == 0) return 0;
    const child = parser.namedChild(node, 0);
    const status = execNode(io, child, source);
    const result: u8 = if (status == 0) 1 else 0;
    recordExitStatus(result);
    return result;
}

fn execTest(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    // [[ ... ]] extended test: evaluate the expression tree
    const ncount = parser.namedChildCount(node);
    if (ncount == 0) return 1;

    const expr = parser.namedChild(node, 0);
    return evalExpr(expr, source);
}

fn evalExpr(node: NodeType, source: []const u8) u8 {
    const name = nodeName(node);

    if (std.mem.eql(u8, name, "word") or std.mem.eql(u8, name, "string") or
        std.mem.eql(u8, name, "raw_string") or std.mem.eql(u8, name, "number") or
        std.mem.eql(u8, name, "simple_expansion") or std.mem.eql(u8, name, "expansion"))
    {
        const raw = nodeText(node, source);
        // Expand the token so variables like $x or "$x" are resolved
        if (expand.expandToken(allocator, raw)) |res| {
            var list = res;
            defer list.deinit();
            if (list.words.len > 0 and list.words[0].len > 0) return 0;
            return 1;
        } else |_| {
            return if (raw.len > 0) 0 else 1;
        }
    }

    if (std.mem.eql(u8, name, "concatenation")) {
        const txt = nodeText(node, source);
        return if (txt.len > 0) 0 else 1;
    }

    if (std.mem.eql(u8, name, "unary_expression")) {
        // Operator is first child (unnamed), operand is first named child
        // or operator is in the "operator" field
        const total = parser.childCount(node);
        const op_node = parser.childAt(node, 0);
        const op_text = nodeText(op_node, source);

        // Find the operand (first named child after the operator)
        var operand: ?NodeType = null;
        for (1..total) |i| {
            const child = parser.childAt(node, @intCast(i));
            const cname = nodeName(child);
            if (std.mem.eql(u8, cname, "word") or std.mem.eql(u8, cname, "string") or
                std.mem.eql(u8, cname, "raw_string") or std.mem.eql(u8, cname, "number") or
                std.mem.eql(u8, cname, "simple_expansion") or std.mem.eql(u8, cname, "expansion") or
                std.mem.eql(u8, cname, "concatenation") or std.mem.eql(u8, cname, "unary_expression") or
                std.mem.eql(u8, cname, "binary_expression") or std.mem.eql(u8, cname, "parenthesized_expression") or
                std.mem.eql(u8, cname, "variable_name")) {
                operand = child;
                break;
            }
        }

        if (std.mem.eql(u8, op_text, "!")) {
            const operand_result = if (operand) |o| evalExpr(o, source) else 1;
            return if (operand_result == 0) 1 else 0;
        }

        // File tests (-d, -f, -r, -w, -x, -e, -s, -L, -n, -z)
        if (operand) |o| {
            const val = expandedNodeText(o, source);
            return testUnaryOp(op_text, val);
        }
        return 1;
    }

    if (std.mem.eql(u8, name, "binary_expression")) {
        // Binary expression: left, operator (unnamed), right
        var left: ?NodeType = null;
        var operator: ?[]const u8 = null;
        var right: ?NodeType = null;

        const total = parser.childCount(node);
        for (0..total) |i| {
            const child = parser.childAt(node, @intCast(i));
            const cname = nodeName(child);
            if (left == null) {
                if (std.mem.eql(u8, cname, "word") or std.mem.eql(u8, cname, "string") or
                    std.mem.eql(u8, cname, "raw_string") or std.mem.eql(u8, cname, "number") or
                    std.mem.eql(u8, cname, "simple_expansion") or std.mem.eql(u8, cname, "expansion") or
                    std.mem.eql(u8, cname, "concatenation") or std.mem.eql(u8, cname, "unary_expression") or
                    std.mem.eql(u8, cname, "binary_expression") or std.mem.eql(u8, cname, "parenthesized_expression") or
                    std.mem.eql(u8, cname, "variable_name")) {
                    left = child;
                }
            } else if (operator == null) {
                operator = nodeText(child, source);
            } else if (right == null) {
                if (std.mem.eql(u8, cname, "word") or std.mem.eql(u8, cname, "string") or
                    std.mem.eql(u8, cname, "raw_string") or std.mem.eql(u8, cname, "number") or
                    std.mem.eql(u8, cname, "simple_expansion") or std.mem.eql(u8, cname, "expansion") or
                    std.mem.eql(u8, cname, "concatenation") or std.mem.eql(u8, cname, "unary_expression") or
                    std.mem.eql(u8, cname, "binary_expression") or std.mem.eql(u8, cname, "parenthesized_expression") or
                    std.mem.eql(u8, cname, "variable_name") or std.mem.eql(u8, cname, "regex")) {
                    right = child;
                }
            }
        }

        const lnode = left orelse return 1;
        const rnode = right orelse return 1;
        const op = operator orelse return 1;

        // Handle logical operators
        if (std.mem.eql(u8, op, "&&")) {
            const lr = evalExpr(lnode, source);
            if (lr != 0) return lr;
            return evalExpr(rnode, source);
        }
        if (std.mem.eql(u8, op, "||")) {
            const lr = evalExpr(lnode, source);
            if (lr == 0) return 0;
            return evalExpr(rnode, source);
        }

        const lval = expandedNodeText(lnode, source);
        const rval = expandedNodeText(rnode, source);

        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "=")) {
            return if (std.mem.eql(u8, lval, rval)) 0 else 1;
        }
        if (std.mem.eql(u8, op, "!=")) {
            return if (!std.mem.eql(u8, lval, rval)) 0 else 1;
        }
        if (std.mem.eql(u8, op, "=~")) {
            // Basic regex matching using the rval as a pattern against lval
            // For now: simple substring match (pattern in string)
            // Full regex would need POSIX regexec()
            if (rval.len == 0) return 1;
            // Simple check: does lval contain rval, or does rval match as glob?
            return if (std.mem.indexOf(u8, lval, rval) != null) 0 else 1;
        }

        // Integer comparisons (-eq, -ne, -lt, -le, -gt, -ge)
        if (std.mem.eql(u8, op, "-eq") or std.mem.eql(u8, op, "-ne") or
            std.mem.eql(u8, op, "-lt") or std.mem.eql(u8, op, "-le") or
            std.mem.eql(u8, op, "-gt") or std.mem.eql(u8, op, "-ge")) {
            const li = std.fmt.parseInt(i64, lval, 10) catch return 1;
            const ri = std.fmt.parseInt(i64, rval, 10) catch return 1;
            if (std.mem.eql(u8, op, "-eq")) return if (li == ri) 0 else 1;
            if (std.mem.eql(u8, op, "-ne")) return if (li != ri) 0 else 1;
            if (std.mem.eql(u8, op, "-lt")) return if (li < ri) 0 else 1;
            if (std.mem.eql(u8, op, "-le")) return if (li <= ri) 0 else 1;
            if (std.mem.eql(u8, op, "-gt")) return if (li > ri) 0 else 1;
            if (std.mem.eql(u8, op, "-ge")) return if (li >= ri) 0 else 1;
        }
        return 1;
    }

    if (std.mem.eql(u8, name, "parenthesized_expression")) {
        const pc = parser.namedChildCount(node);
        if (pc > 0) return evalExpr(parser.namedChild(node, 0), source);
        return 1;
    }

    if (std.mem.eql(u8, name, "variable_name")) {
        const vname = nodeText(node, source);
        if (var_store.get(vname)) |v| {
            return if (v.value.len > 0) 0 else 1;
        }
        return 1;
    }

    return 1;
}

fn expandedNodeText(node: NodeType, source: []const u8) []const u8 {
    const raw = nodeText(node, source);
    if (expand.expandToken(allocator, raw)) |res| {
        var list = res;
        defer list.deinit();
        if (list.words.len > 0) {
            return allocator.dupe(u8, list.words[0]) catch raw;
        }
        return "";
    } else |_| {
        return raw;
    }
}

fn testUnaryOp(op: []const u8, val: []const u8) u8 {
    var buf: [4096]u8 = undefined;
    if (val.len >= buf.len) return 1;
    @memcpy(buf[0..val.len], val);
    buf[val.len] = 0;
    const path = buf[0..val.len :0];

    if (std.mem.eql(u8, op, "-z")) return if (val.len == 0) 0 else 1;
    if (std.mem.eql(u8, op, "-n")) return if (val.len > 0) 0 else 1;

    if (std.mem.eql(u8, op, "-d") or std.mem.eql(u8, op, "-f") or std.mem.eql(u8, op, "-r") or
        std.mem.eql(u8, op, "-w") or std.mem.eql(u8, op, "-x") or std.mem.eql(u8, op, "-e") or
        std.mem.eql(u8, op, "-s") or std.mem.eql(u8, op, "-L")) {
        var st: c.struct_stat = undefined;
        if (c.stat(path, &st) != 0) return 1;
        if (std.mem.eql(u8, op, "-e")) return 0;

        const st_mode = st.st_mode;
        if (std.mem.eql(u8, op, "-d")) return if (st_mode & c.S_IFMT == c.S_IFDIR) 0 else 1;
        if (std.mem.eql(u8, op, "-f")) return if (st_mode & c.S_IFMT == c.S_IFREG) 0 else 1;
        if (std.mem.eql(u8, op, "-r")) return if (st_mode & c.S_IRUSR != 0) 0 else 1;
        if (std.mem.eql(u8, op, "-w")) return if (st_mode & c.S_IWUSR != 0) 0 else 1;
        if (std.mem.eql(u8, op, "-x")) return if (st_mode & c.S_IXUSR != 0) 0 else 1;
        if (std.mem.eql(u8, op, "-s")) return if (st.st_size > 0) 0 else 1;
        if (std.mem.eql(u8, op, "-L")) {
            var lst: c.struct_stat = undefined;
            if (c.lstat(path, &lst) != 0) return 1;
            return if ((lst.st_mode & c.S_IFMT) == c.S_IFLNK) 0 else 1;
        }
    }

    return 1;
}

fn execVarAssign(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    const text = nodeText(node, source);
    if (std.mem.indexOfScalar(u8, text, '=')) |eq| {
        const name = text[0..eq];
        const value = text[eq + 1 ..];
        if (expand.expandToken(allocator, value)) |res| {
            var result = res;
            defer result.deinit();
            if (result.words.len > 0) {
                var_store.setLocal(name, result.words[0], false);
            } else {
                var_store.setLocal(name, "", false);
            }
        } else |_| {
            var_store.setLocal(name, "", false);
        }
    }
    return 0;
}

fn execExport(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    const count = parser.childCount(node);
    for (0..count) |i| {
        const child = parser.childAt(node, @intCast(i));
        const cname = nodeName(child);
        if (std.mem.eql(u8, cname, "variable_assignment")) {
            const text = nodeText(child, source);
            if (std.mem.indexOfScalar(u8, text, '=')) |eq| {
                const name = text[0..eq];
                const value = text[eq + 1 ..];
                if (expand.expandToken(allocator, value)) |res| {
                    var result = res;
                    defer result.deinit();
                    if (result.words.len > 0) {
                        var_store.set(name, result.words[0], true);
                    } else {
                        var_store.set(name, "", true);
                    }
                } else |_| {
                    var_store.set(name, "", true);
                }
            }
        } else if (std.mem.eql(u8, cname, "word")) {
            const name = nodeText(child, source);
            if (!std.mem.startsWith(u8, name, "-")) {
                if (var_store.get(name)) |v| {
                    var_store.set(name, v.value, true);
                }
            }
        }
    }
    return 0;
}

fn execCase(io: std.Io, node: NodeType, source: []const u8) u8 {
    const ncount = parser.namedChildCount(node);
    if (ncount < 2) return 0;

    // First named child is the tested value
    const value_node = parser.namedChild(node, 0);
    const value_text = nodeText(value_node, source);

    // Case items follow (case_item nodes)
    for (1..ncount) |i| {
        const item = parser.namedChild(node, @intCast(i));
        const iname = nodeName(item);
        if (!std.mem.eql(u8, iname, "case_item")) continue;

        const item_count = parser.namedChildCount(item);
        if (item_count == 0) continue;

        // Last named child is the body (maybe)
        // Patterns are before the body

        // Find patterns: named children that are word/string/expansion
        var patterns: std.ArrayListAligned([]const u8, null) = .empty;
        defer patterns.deinit(allocator);

        var item_body: ?NodeType = null;
        for (0..item_count) |j| {
            const child = parser.namedChild(item, @intCast(j));
            const cname = nodeName(child);
            if (std.mem.eql(u8, cname, "word") or std.mem.eql(u8, cname, "string") or
                std.mem.eql(u8, cname, "raw_string") or std.mem.eql(u8, cname, "simple_expansion"))
            {
                const pat = nodeText(child, source);
                patterns.append(allocator, pat) catch @panic("oom");
            } else {
                // Assume this is the body command
                item_body = child;
            }
        }

        // Check if value matches any pattern (simple string comparison for now)
        var matched = false;
        for (patterns.items) |pat| {
            // Simple glob-like matching: if pattern contains * or ? use simple matching
            if (std.mem.indexOfScalar(u8, pat, '*') != null) {
                // Prefix/suffix match: *foo, foo*, *foo*
                if (std.mem.startsWith(u8, pat, "*") and std.mem.endsWith(u8, pat, "*") and pat.len >= 2) {
                    const inner = pat[1 .. pat.len - 1];
                    if (std.mem.indexOf(u8, value_text, inner) != null) {
                        matched = true;
                        break;
                    }
                } else if (std.mem.startsWith(u8, pat, "*")) {
                    const suffix = pat[1..];
                    if (std.mem.endsWith(u8, value_text, suffix)) {
                        matched = true;
                        break;
                    }
                } else if (std.mem.endsWith(u8, pat, "*")) {
                    const prefix = pat[0 .. pat.len - 1];
                    if (std.mem.startsWith(u8, value_text, prefix)) {
                        matched = true;
                        break;
                    }
                }
            } else if (std.mem.eql(u8, value_text, pat)) {
                matched = true;
                break;
            }
        }

        if (matched) {
            if (item_body) |body| {
                return execNode(io, body, source);
            }
            return 0;
        }
    }

    return 0;
}

fn execBuiltinEval(io: std.Io, source: []const u8, args: [][]const u8) u8 {
    _ = source;
    if (args.len < 2) return 0;
    // Concatenate arguments with spaces
    var total_len: usize = 0;
    for (args[1..]) |a| {
        total_len += a.len + 1;
    }
    const cmd = allocator.alloc(u8, total_len) catch @panic("oom");
    defer allocator.free(cmd);
    var pos: usize = 0;
    for (args[1..], 0..) |a, i| {
        if (i > 0) {
            cmd[pos] = ' ';
            pos += 1;
        }
        @memcpy(cmd[pos..pos + a.len], a);
        pos += a.len;
    }
    const cmd_z = allocator.dupeZ(u8, cmd) catch @panic("oom");
    defer allocator.free(cmd_z);
    const tree = parser.parseString(cmd_z) orelse return 1;
    defer parser.treeDelete(tree);
    return exec(io, tree, cmd);
}

fn execBuiltinSource(io: std.Io, args: [][]const u8) u8 {
    if (args.len < 2) return 0;
    const path = args[1];
    const content = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: No such file or directory\n", .{path}) catch "error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 1;
    };
    defer allocator.free(content);
    const content_z = allocator.dupeZ(u8, content) catch @panic("oom");
    defer allocator.free(content_z);
    const tree = parser.parseString(content_z) orelse return 1;
    defer parser.treeDelete(tree);
    return exec(io, tree, content);
}

fn execBuiltinExec(io: std.Io, args: [][]const u8) u8 {
    if (args.len < 2) return 0;
    // Build C-style argv
    const argv = allocator.alloc([*c]u8, args.len) catch @panic("oom");
    defer allocator.free(argv);
    for (args[1..], 0..) |a, i| {
        const arg_z = allocator.dupeZ(u8, a) catch @panic("oom");
        argv[i] = arg_z.ptr;
    }
    argv[args.len - 1] = null;
    const cmd_z = allocator.dupeZ(u8, args[1]) catch @panic("oom");
    _ = c.execvp(cmd_z.ptr, argv.ptr);
    // If execvp fails, process continues
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "exec: {s}: not found\n", .{args[1]}) catch "exec error\n";
    _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
    return 127;
}

fn execFnDef(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    const ncount = parser.namedChildCount(node);
    if (ncount < 2) return 1;

    const name_node = parser.namedChild(node, 0);
    const name = nodeText(name_node, source);

    // Store in function table (the function_definition node itself)
    functions.put(name, node) catch {};

    return 0;
}

fn execDeclaration(io: std.Io, node: NodeType, source: []const u8) u8 {
    var last: u8 = 0;
    const count = parser.childCount(node);
    for (0..count) |i| {
        const child = parser.childAt(node, i);
        last = execNode(io, child, source);
    }
    return last;
}

fn execUnset(io: std.Io, node: NodeType, source: []const u8) u8 {
    _ = io;
    const count = parser.childCount(node);
    for (0..count) |i| {
        const child = parser.childAt(node, i);
        const cname = nodeName(child);
        var is_skip = false;
        inline for (.{ "redirected_statement", "heredoc_body", "file_redirect",
            "file_descriptor", "herestring_redirect", "heredoc_start", "variable_assignment" }) |st| {
            if (std.mem.eql(u8, cname, st)) {
                is_skip = true;
            }
        }
        if (is_skip) continue;

        const raw = nodeText(child, source);
        var_store.unset(raw);
    }
    return 0;
}
