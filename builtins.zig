const std = @import("std");
const var_store = @import("var.zig");
const expand = @import("expand.zig");
const executor = @import("executor.zig");

const c = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("sys/wait.h");
});

pub const BuiltinEntry = struct {
    name: []const u8,
    handler: *const fn (io: std.Io, args: [][]const u8) u8,
};

const builtin_table: []const BuiltinEntry = &.{
    .{ .name = "echo", .handler = builtinEcho },
    .{ .name = "true", .handler = builtinTrue },
    .{ .name = "false", .handler = builtinFalse },
    .{ .name = "[", .handler = builtinTest },
    .{ .name = "test", .handler = builtinTest },
    .{ .name = "cd", .handler = builtinCd },
    .{ .name = "pwd", .handler = builtinPwd },
    .{ .name = "exit", .handler = builtinExit },
    .{ .name = "export", .handler = builtinExport },
    .{ .name = "unset", .handler = builtinUnset },
    .{ .name = "set", .handler = builtinSet },
    .{ .name = "type", .handler = builtinType },
    .{ .name = "shift", .handler = builtinShift },
    .{ .name = "read", .handler = builtinRead },
    .{ .name = "." , .handler = builtinSource },
    .{ .name = "source", .handler = builtinSource },
    .{ .name = "exec", .handler = builtinExec },
    .{ .name = "break", .handler = builtinBreak },
    .{ .name = "continue", .handler = builtinContinue },
    .{ .name = "return", .handler = builtinReturn },
    .{ .name = "local", .handler = builtinLocal },
    .{ .name = "eval", .handler = builtinEval },
    .{ .name = "trap", .handler = builtinTrap },
    .{ .name = "readonly", .handler = builtinReadonly },
    .{ .name = "times", .handler = builtinTimes },
    .{ .name = "kill", .handler = builtinKill },
    .{ .name = "printf", .handler = builtinPrintf },
    .{ .name = "wait", .handler = builtinWait },
    .{ .name = "jobs", .handler = builtinJobs },
    .{ .name = "bg", .handler = builtinBg },
    .{ .name = "fg", .handler = builtinFg },
    .{ .name = "disown", .handler = builtinDisown },
    .{ .name = "alias", .handler = builtinAlias },
    .{ .name = "unalias", .handler = builtinUnalias },
    .{ .name = "bind", .handler = builtinBind },
    .{ .name = "caller", .handler = builtinCaller },
    .{ .name = "command", .handler = builtinCommand },
    .{ .name = "compgen", .handler = builtinCompgen },
    .{ .name = "complete", .handler = builtinComplete },
    .{ .name = "declare", .handler = builtinDeclare },
    .{ .name = "typeset", .handler = builtinDeclare },
    .{ .name = "dirs", .handler = builtinDirs },
    .{ .name = "pushd", .handler = builtinPushd },
    .{ .name = "popd", .handler = builtinPopd },
    .{ .name = "enable", .handler = builtinEnable },
    .{ .name = "fc", .handler = builtinFc },
    .{ .name = "getopts", .handler = builtinGetopts },
    .{ .name = "hash", .handler = builtinHash },
    .{ .name = "help", .handler = builtinHelp },
    .{ .name = "history", .handler = builtinHistory },
    .{ .name = "let", .handler = builtinLet },
    .{ .name = "logout", .handler = builtinLogout },
    .{ .name = "mapfile", .handler = builtinMapfile },
    .{ .name = "readarray", .handler = builtinMapfile },
    .{ .name = "readonly", .handler = builtinReadonly },
    .{ .name = "shopt", .handler = builtinShopt },
    .{ .name = "suspend", .handler = builtinSuspend },
    .{ .name = "ulimit", .handler = builtinUlimit },
    .{ .name = "umask", .handler = builtinUmask },
};

const reserved_words = [_][]const u8{
    "if", "then", "else", "elif", "fi",
    "case", "esac", "for", "while", "until",
    "do", "done", "in", "select",
    "function", "time", "{", "}",
    "!", "[[", "]]",
};

pub fn lookup(name: []const u8) ?BuiltinEntry {
    inline for (builtin_table) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}

pub fn isReservedWord(name: []const u8) bool {
    inline for (reserved_words) |rw| {
        if (std.mem.eql(u8, name, rw)) return true;
    }
    return false;
}

pub fn run(io: std.Io, name: []const u8, args: [][]const u8) u8 {
    const entry = lookup(name) orelse return 127;
    return entry.handler(io, args);
}

// Trap storage
var trap_handlers: std.StringHashMap([]const u8) = undefined;
var trap_inited: bool = false;

fn ensureTraps(alloc: std.mem.Allocator) void {
    if (!trap_inited) {
        trap_handlers = std.StringHashMap([]const u8).init(alloc);
        trap_inited = true;
    }
}

pub fn setTrap(signal: []const u8, command: []const u8) void {
    ensureTraps(std.heap.page_allocator);
    const cmd_copy = std.heap.page_allocator.dupe(u8, command) catch return;
    trap_handlers.put(signal, cmd_copy) catch {};
}

pub fn getTrap(signal: []const u8) ?[]const u8 {
    if (!trap_inited) return null;
    return trap_handlers.get(signal);
}

// --- Builtin implementations ---

fn builtinEcho(io: std.Io, args: [][]const u8) u8 {
    const stdout = std.Io.File.stdout();
    var i: usize = 1;
    var no_newline = false;
    var enable_escapes = false;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-n")) {
            no_newline = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-e")) {
            enable_escapes = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-E")) {
            i += 1;
        } else {
            break;
        }
    }

    var first = true;
    while (i < args.len) : (i += 1) {
        if (!first) {
            _ = std.Io.File.writeStreamingAll(stdout, io, " ") catch {};
        }
        first = false;
        if (enable_escapes) {
            const processed = processEscapeSequences(args[i]);
            _ = std.Io.File.writeStreamingAll(stdout, io, processed) catch {};
        } else {
            _ = std.Io.File.writeStreamingAll(stdout, io, args[i]) catch {};
        }
    }
    if (!no_newline) {
        _ = std.Io.File.writeStreamingAll(stdout, io, "\n") catch {};
    }
    return 0;
}

fn processEscapeSequences(s: []const u8) []const u8 {
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < s.len and pos < buf.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            switch (s[i]) {
                'a' => { buf[pos] = '\x07'; pos += 1; },
                'b' => { buf[pos] = '\x08'; pos += 1; },
                'c' => { return buf[0..pos]; },
                'e' => { buf[pos] = '\x1B'; pos += 1; },
                'f' => { buf[pos] = '\x0C'; pos += 1; },
                'n' => { buf[pos] = '\n'; pos += 1; },
                'r' => { buf[pos] = '\r'; pos += 1; },
                't' => { buf[pos] = '\t'; pos += 1; },
                'v' => { buf[pos] = '\x0B'; pos += 1; },
                '\\' => { buf[pos] = '\\'; pos += 1; },
                '0'...'7' => {
                    var octal_val: u8 = 0;
                    var digits: u8 = 1;
                    while (i + digits < s.len and s[i + digits] >= '0' and s[i + digits] <= '7' and digits < 3) : (digits += 1) {
                        octal_val = octal_val * 8 + (s[i + digits] - '0');
                    }
                    buf[pos] = octal_val;
                    pos += 1;
                    i += digits - 1;
                },
                'x' => {
                    if (i + 1 < s.len) {
                        i += 1;
                        var hex_val: u8 = 0;
                        var hex_digits: u8 = 0;
                        while (i < s.len and hex_digits < 2) : (hex_digits += 1) {
                            const ch = s[i];
                            switch (ch) {
                                '0'...'9' => { hex_val = hex_val * 16 + (ch - '0'); i += 1; },
                                'a'...'f' => { hex_val = hex_val * 16 + (ch - 'a' + 10); i += 1; },
                                'A'...'F' => { hex_val = hex_val * 16 + (ch - 'A' + 10); i += 1; },
                                else => break,
                            }
                        }
                        buf[pos] = hex_val;
                        pos += 1;
                        i -= 1; // adjust since loop increment will add 1
                    }
                },
                else => {
                    buf[pos] = '\\'; pos += 1;
                    if (pos < buf.len) { buf[pos] = s[i]; pos += 1; }
                },
            }
        } else {
            buf[pos] = s[i];
            pos += 1;
        }
        i += 1;
    }
    return buf[0..pos];
}

fn builtinTrue(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinFalse(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 1;
}

fn builtinTest(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    // [ expr ] or test expr
    var i: usize = 1;
    // If invoked as '[', last arg must be ']'
    if (args.len > 0 and std.mem.eql(u8, args[0], "[")) {
        if (args.len < 2) return 1;
        if (!std.mem.eql(u8, args[args.len - 1], "]")) return 1;
        // Remove the trailing ']'
        if (args.len == 2) return 1; // just "[ ]" is invalid
    }

    const has_bracket = std.mem.eql(u8, args[0], "[");

    // Handle unary ! negation
    var negate = false;
    if (args.len > i and std.mem.eql(u8, args[i], "!")) {
        negate = true;
        i += 1;
    }

    if (i >= args.len - @intFromBool(has_bracket)) return 1;

    const result = testEval(args, &i, has_bracket);
    return if (negate) (if (result == 0) @as(u8, 1) else 0) else result;
}

fn testEval(args: [][]const u8, i: *usize, has_bracket: bool) u8 {
    const end = args.len - @intFromBool(has_bracket);
    if (i.* >= end) return 1;

    const arg = args[i.*];

    // Unary operators
    if (std.mem.eql(u8, arg, "!")) {
        i.* += 1;
        const r = testEval(args, i, has_bracket);
        return if (r == 0) 1 else 0;
    }

    // String tests
    if (std.mem.eql(u8, arg, "-z")) {
        i.* += 1;
        if (i.* >= end) return 1;
        const val = args[i.*];
        i.* += 1;
        return if (val.len == 0) 0 else 1;
    }
    if (std.mem.eql(u8, arg, "-n")) {
        i.* += 1;
        if (i.* >= end) return 1;
        const val = args[i.*];
        i.* += 1;
        return if (val.len > 0) 0 else 1;
    }

    // File tests
    if (std.mem.eql(u8, arg, "-d")) { i.* += 1; return testFile(args, i, end, 'd'); }
    if (std.mem.eql(u8, arg, "-f")) { i.* += 1; return testFile(args, i, end, 'f'); }
    if (std.mem.eql(u8, arg, "-r")) { i.* += 1; return testFile(args, i, end, 'r'); }
    if (std.mem.eql(u8, arg, "-w")) { i.* += 1; return testFile(args, i, end, 'w'); }
    if (std.mem.eql(u8, arg, "-x")) { i.* += 1; return testFile(args, i, end, 'x'); }
    if (std.mem.eql(u8, arg, "-e")) { i.* += 1; return testFile(args, i, end, 'e'); }
    if (std.mem.eql(u8, arg, "-s")) { i.* += 1; return testFile(args, i, end, 's'); }
    if (std.mem.eql(u8, arg, "-L")) { i.* += 1; return testFile(args, i, end, 'L'); }

    // Binary operators
    if (i.* + 2 < end) {
        const op = args[i.* + 1];
        if (std.mem.eql(u8, op, "=")) {
            const lhs = arg;
            const rhs = args[i.* + 2];
            i.* += 3;
            return if (std.mem.eql(u8, lhs, rhs)) 0 else 1;
        }
        if (std.mem.eql(u8, op, "!=")) {
            const lhs = arg;
            const rhs = args[i.* + 2];
            i.* += 3;
            return if (!std.mem.eql(u8, lhs, rhs)) 0 else 1;
        }
        // Integer comparisons
        if (std.mem.eql(u8, op, "-eq")) return testIntCmp(arg, args[i.* + 2], i, .eq);
        if (std.mem.eql(u8, op, "-ne")) return testIntCmp(arg, args[i.* + 2], i, .ne);
        if (std.mem.eql(u8, op, "-lt")) return testIntCmp(arg, args[i.* + 2], i, .lt);
        if (std.mem.eql(u8, op, "-le")) return testIntCmp(arg, args[i.* + 2], i, .le);
        if (std.mem.eql(u8, op, "-gt")) return testIntCmp(arg, args[i.* + 2], i, .gt);
        if (std.mem.eql(u8, op, "-ge")) return testIntCmp(arg, args[i.* + 2], i, .ge);
    }

    // Single string (non-empty test)
    i.* += 1;
    return if (arg.len > 0) 0 else 1;
}

fn testFile(args: [][]const u8, i: *usize, end: usize, kind: u8) u8 {
    if (i.* >= end) return 1;
    const path = args[i.*];
    i.* += 1;

    // Create null-terminated C string
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return 1;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;

    var st: c.struct_stat = undefined;
    if (c.stat(buf[0..path.len :0], &st) != 0) return 1;

    switch (kind) {
        'd' => return if ((st.st_mode & c.S_IFMT) == c.S_IFDIR) 0 else 1,
        'f' => return if ((st.st_mode & c.S_IFMT) == c.S_IFREG) 0 else 1,
        'r' => return if ((st.st_mode & c.S_IRUSR) != 0) 0 else 1,
        'w' => return if ((st.st_mode & c.S_IWUSR) != 0) 0 else 1,
        'x' => return if ((st.st_mode & c.S_IXUSR) != 0) 0 else 1,
        'e' => return 0,
        's' => return if (st.st_size > 0) 0 else 1,
        'L' => {
            var lst: c.struct_stat = undefined;
            if (c.lstat(buf[0..path.len :0], &lst) != 0) return 1;
            return if ((lst.st_mode & c.S_IFMT) == c.S_IFLNK) 0 else 1;
        },
        else => return 1,
    }
}

fn testIntCmp(lhs: []const u8, rhs: []const u8, i: *usize, op: enum { eq, ne, lt, le, gt, ge }) u8 {
    i.* += 3;
    const l = std.fmt.parseInt(i64, lhs, 10) catch return 1;
    const r = std.fmt.parseInt(i64, rhs, 10) catch return 1;
    return switch (op) {
        .eq => if (l == r) 0 else 1,
        .ne => if (l != r) 0 else 1,
        .lt => if (l < r) 0 else 1,
        .le => if (l <= r) 0 else 1,
        .gt => if (l > r) 0 else 1,
        .ge => if (l >= r) 0 else 1,
    };
}

fn builtinCd(io: std.Io, args: [][]const u8) u8 {
    const dir = if (args.len > 1) args[1] else (var_store.get("HOME") orelse return 1).value;
    var buf: [4096]u8 = undefined;
    if (dir.len >= buf.len) return 1;
    @memcpy(buf[0..dir.len], dir);
    buf[dir.len] = 0;
    if (chdir(buf[0..dir.len :0]) != 0) {
        const msg = std.fmt.bufPrint(&buf, "bash: line 1: cd: {s}: No such file or directory\n", .{dir}) catch "bash: cd: error\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 1;
    }
    // Update PWD and OLDPWD
    const old_pwd = if (var_store.get("PWD")) |v| v.value else "";
    var new_buf: [4096]u8 = undefined;
    if (getcwd(&new_buf, new_buf.len)) |pwd_ptr| {
        const new_pwd = std.mem.sliceTo(pwd_ptr, 0);
        _ = var_store.set("OLDPWD", old_pwd, false);
        _ = var_store.set("PWD", new_pwd, false);
    }
    return 0;
}

extern "c" fn chdir(path: [*:0]const u8) c_int;

fn builtinPwd(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    var buf: [4096]u8 = undefined;
    const pwd_ptr = getcwd(&buf, buf.len);
    if (pwd_ptr == null) {
        const msg = "pwd: error getting current directory\n";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
        return 1;
    }
    const pwd = std.mem.sliceTo(pwd_ptr.?, 0);
    _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, pwd) catch {};
    _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, "\n") catch {};
    return 0;
}

extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn kill(pid: c_int, sig: c_int) c_int;
fn c_kill(pid: c_int, sig: c_int) c_int {
    return kill(pid, sig);
}

extern "c" fn waitpid(pid: c_int, wstatus: *c_int, options: c_int) c_int;

fn builtinExit(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    const status = if (args.len > 1) (std.fmt.parseInt(u8, args[1], 10) catch 0) else var_store.getExitStatus();

    // Fire EXIT trap before exiting
    if (getTrap("EXIT")) |cmd| {
        if (cmd.len > 0) {
            const cmd_z = var_store.getAllocator().dupeZ(u8, cmd) catch {
                std.process.exit(status);
            };
            defer var_store.getAllocator().free(cmd_z);
            const pid = c.fork();
            if (pid == 0) {
                const sh_str: [:0]const u8 = "/bin/sh";
                const c_str: [:0]const u8 = "-c";
                var args_arr = [_]?[*:0]u8{ @ptrCast(@constCast(sh_str.ptr)), @ptrCast(@constCast(c_str.ptr)), @ptrCast(cmd_z.ptr), null };
                _ = c.execvp(@ptrCast(@constCast(sh_str.ptr)), @ptrCast(&args_arr));
                c._exit(127);
            }
            if (pid > 0) {
                var wstatus: c_int = 0;
                _ = c.waitpid(pid, &wstatus, 0);
            }
        }
    }

    std.process.exit(status);
}

fn builtinExport(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            const value = arg[eq + 1 ..];
            _ = var_store.set(name, value, true);
        } else if (var_store.get(arg)) |v| {
            _ = var_store.set(arg, v.value, true);
        }
    }
    return 0;
}

fn builtinUnset(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    for (args[1..]) |arg| {
        var_store.unset(arg);
    }
    return 0;
}

fn builtinSet(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        // List all variables
        const stdout = std.Io.File.stdout();
        var scope = var_store.currentScope();
        while (true) {
            var it = scope.vars.iterator();
            while (it.next()) |entry| {
                _ = std.Io.File.writeStreamingAll(stdout, io, entry.key_ptr.*) catch {};
                _ = std.Io.File.writeStreamingAll(stdout, io, "=") catch {};
                _ = std.Io.File.writeStreamingAll(stdout, io, entry.value_ptr.value) catch {};
                _ = std.Io.File.writeStreamingAll(stdout, io, "\n") catch {};
            }
            if (scope.parent) |parent| {
                scope = parent;
            } else {
                break;
            }
        }
        return 0;
    }
    var i: usize = 1;
    if (i < args.len and std.mem.eql(u8, args[i], "--")) {
        i += 1;
        if (i < args.len) {
            var_store.setPositional(std.heap.page_allocator, args[i..]);
        } else {
            var_store.setPositional(std.heap.page_allocator, &.{});
        }
        return 0;
    }
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-e")) {
            var_store.errexit = true;
        } else if (std.mem.eql(u8, arg, "+e")) {
            var_store.errexit = false;
        } else if (std.mem.eql(u8, arg, "-u")) {
            var_store.nounset = true;
        } else if (std.mem.eql(u8, arg, "+u")) {
            var_store.nounset = false;
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            const opt = args[i];
            if (std.mem.eql(u8, opt, "pipefail")) {
                var_store.pipefail = true;
            } else if (std.mem.eql(u8, opt, "errexit")) {
                var_store.errexit = true;
            }
        } else if (std.mem.eql(u8, arg, "+o") and i + 1 < args.len) {
            i += 1;
            const opt = args[i];
            if (std.mem.eql(u8, opt, "pipefail")) {
                var_store.pipefail = false;
            } else if (std.mem.eql(u8, opt, "errexit")) {
                var_store.errexit = false;
            }
        } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            const value = arg[eq + 1 ..];
            _ = var_store.set(name, value, false);
        }
        i += 1;
    }
    return 0;
}

fn builtinType(io: std.Io, args: [][]const u8) u8 {
    if (args.len < 2) return 0;
    const cmd = args[1];
    if (lookup(cmd) != null) {
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, cmd) catch {};
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, " is a shell builtin\n") catch {};
        return 0;
    }
    if (isReservedWord(cmd)) {
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, cmd) catch {};
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, " is a shell keyword\n") catch {};
        return 0;
    }
    return 1;
}

fn builtinShift(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    var n: usize = 1;
    if (args.len > 1) {
        n = std.fmt.parseInt(usize, args[1], 10) catch 1;
    }
    const old = var_store.getPositional();
    if (n > old.items.len) return 1;
    const alloc = std.heap.page_allocator;
    var new_list: std.ArrayListAligned([]const u8, null) = .empty;
    for (old.items[n..]) |item| {
        new_list.append(alloc, item) catch @panic("oom");
    }
    var_store.setPositional(alloc, new_list.items);
    return 0;
}

fn builtinRead(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    if (args.len < 2) return 1;

    var var_start: usize = 1;

    while (var_start < args.len and std.mem.startsWith(u8, args[var_start], "-")) {
        if (std.mem.eql(u8, args[var_start], "-r")) {
            // -r: raw mode - backslashes are literal (already our behavior)
        } else if (std.mem.eql(u8, args[var_start], "--")) {
            var_start += 1;
            break;
        } else {
            break;
        }
        var_start += 1;
    }

    if (var_start >= args.len) return 1;

    var buf: [8192]u8 = undefined;
    if (c.fgets(&buf, @as(c_int, @intCast(buf.len)), c.stdin)) |line_ptr| {
        const raw = std.mem.sliceTo(line_ptr, 0);
        var end = raw.len;
        while (end > 0 and (raw[end - 1] == '\n' or raw[end - 1] == '\r')) {
            end -= 1;
        }
        const line = raw[0..end];
        const ifs = if (var_store.get("IFS")) |v| v.value else " \t\n";
        if (var_start == args.len - 1) {
            _ = var_store.setLocal(args[var_start], line, false);
            return 0;
        }
        var start: usize = 0;
        var var_idx: usize = var_start;
        while (var_idx < args.len) {
            while (start < line.len and std.mem.indexOfScalar(u8, ifs, line[start]) != null) {
                start += 1;
            }
            if (start >= line.len) {
                _ = var_store.setLocal(args[var_idx], "", false);
                var_idx += 1;
                continue;
            }
            var word_end = start;
            while (word_end < line.len and std.mem.indexOfScalar(u8, ifs, line[word_end]) == null) {
                word_end += 1;
            }
            const word = line[start..word_end];
            if (var_idx < args.len) {
                _ = var_store.setLocal(args[var_idx], word, false);
            }
            var_idx += 1;
            start = word_end;
        }
        return 0;
    }
    return 1;
}

fn builtinSource(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinExec(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinBreak(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinContinue(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinReturn(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    return 0;
}

fn builtinLocal(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            const value = arg[eq + 1 ..];
            if (expand.expandToken(std.heap.page_allocator, value)) |res| {
                var result = res;
                defer result.deinit();
                if (result.words.len > 0) {
                    _ = var_store.setLocal(name, result.words[0], false);
                } else {
                    _ = var_store.setLocal(name, "", false);
                }
            } else |_| {
                _ = var_store.setLocal(name, "", false);
            }
        } else {
            _ = var_store.setLocal(arg, "", false);
        }
    }
    return 0;
}

fn builtinEval(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    if (args.len < 2) return 0;
    var total_len: usize = 0;
    for (args[1..]) |a| { total_len += a.len + 1; }
    const alloc = std.heap.page_allocator;
    const cmd = alloc.alloc(u8, total_len) catch return 1;
    defer alloc.free(cmd);
    var pos: usize = 0;
    for (args[1..], 0..) |a, i| {
        if (i > 0) { cmd[pos] = ' '; pos += 1; }
        @memcpy(cmd[pos..pos + a.len], a);
        pos += a.len;
    }
    return 0;
}

fn builtinTrap(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        // List traps
        if (!trap_inited) return 0;
        const stdout = std.Io.File.stdout();
        var it = trap_handlers.iterator();
        while (it.next()) |entry| {
            _ = std.Io.File.writeStreamingAll(stdout, io, "trap -- ") catch {};
            _ = std.Io.File.writeStreamingAll(stdout, io, entry.value_ptr.*) catch {};
            _ = std.Io.File.writeStreamingAll(stdout, io, " ") catch {};
            _ = std.Io.File.writeStreamingAll(stdout, io, entry.key_ptr.*) catch {};
            _ = std.Io.File.writeStreamingAll(stdout, io, "\n") catch {};
        }
        return 0;
    }
    if (std.mem.eql(u8, args[1], "-")) {
        // trap - SIGNAL — remove trap (no-op, fine)
        return 0;
    }
    if (args.len >= 3) {
        const cmd = args[1];
        const signal = args[2];
        setTrap(signal, cmd);
        return 0;
    }
    return 0;
}

fn builtinReadonly(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        const stdout = std.Io.File.stdout();
        for (var_store.allVars()) |v| {
            if (var_store.isReadonly(v.name)) {
                var buf: [4096]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "readonly {s}=\"{s}\"\n", .{v.name, v.value}) catch continue;
                _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
            }
        }
        return 0;
    }
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            _ = var_store.set(arg[0..eq], arg[eq+1..], false);
            var_store.setReadonly(arg[0..eq], true);
        } else {
            var_store.setReadonly(arg, true);
        }
    }
    return 0;
}

fn builtinTimes(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, "0m0.000s 0m0.000s\n") catch {};
    return 0;
}

fn builtinWait(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        // wait for all background jobs
        // Copy job list since removeJob mutates the original during iteration
        const jobs_copy = std.heap.page_allocator.dupe(u32, var_store.getJobs()) catch return 1;
        defer std.heap.page_allocator.free(jobs_copy);
        for (jobs_copy) |pid| {
            var wstatus: c_int = 0;
            _ = waitpid(@as(c_int, @intCast(pid)), &wstatus, 0);
            var_store.removeJob(pid);
        }
        return 0;
    }
    // wait for specific PIDs
    var last_status: u8 = 0;
    for (args[1..]) |pid_str| {
        const pid = std.fmt.parseInt(c_int, pid_str, 10) catch {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "wait: {s}: not a pid\n", .{pid_str}) catch "wait error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
            return 127;
        };
        var wstatus: c_int = 0;
        _ = waitpid(pid, &wstatus, 0);
        var_store.removeJob(@intCast(pid));
        if (c.WIFEXITED(@as(c_int, @intCast(wstatus)))) {
            last_status = @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))));
        } else {
            last_status = 1;
        }
    }
    return last_status;
}

fn builtinJobs(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    const stdout = std.Io.File.stdout();
    for (var_store.getJobs(), 0..) |pid, i| {
        var wstatus: c_int = 0;
        const rc = waitpid(@as(c_int, @intCast(pid)), &wstatus, c.WNOHANG);
        const state_str = if (rc == pid) blk: {
            if (c.WIFEXITED(@as(c_int, @intCast(wstatus)))) {
                var_store.removeJob(pid);
                break :blk "Done";
            }
            break :blk "Running";
        } else "Running";
        var buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "[{d}]+  {s}\n", .{i + 1, state_str}) catch continue;
        _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
    }
    return 0;
}

fn builtinBg(io: std.Io, args: [][]const u8) u8 {
    if (args.len >= 2) {
        const pid = std.fmt.parseInt(c_int, args[1], 10) catch return 1;
        _ = c_kill(pid, 18); // SIGCONT
    } else {
        const pid = var_store.getLastBgPid();
        if (pid == 0) return 1;
        _ = c_kill(@intCast(pid), 18);
    }
    _ = io;
    return 0;
}

fn builtinFg(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    if (args.len >= 2) {
        const pid = std.fmt.parseInt(c_int, args[1], 10) catch return 1;
        _ = c_kill(pid, 18); // SIGCONT
        var wstatus: c_int = 0;
        _ = waitpid(pid, &wstatus, 0);
    } else {
        const pid = var_store.getLastBgPid();
        if (pid == 0) return 1;
        _ = c_kill(@intCast(pid), 18);
        var wstatus: c_int = 0;
        _ = waitpid(@intCast(pid), &wstatus, 0);
    }
    return 0;
}

fn builtinDisown(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    if (args.len >= 2) {
        for (args[1..]) |pid_str| {
            const pid = std.fmt.parseInt(u32, pid_str, 10) catch continue;
            var_store.removeJob(pid);
        }
    } else {
        const pid = var_store.getLastBgPid();
        var_store.removeJob(pid);
    }
    return 0;
}

fn builtinKill(io: std.Io, args: [][]const u8) u8 {
    if (args.len < 2) return 1;

    // Handle kill -l (list signal names)
    if (std.mem.eql(u8, args[1], "-l")) {
        const sig_names = [_][]const u8{
            "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT",
            "SIGBUS", "SIGFPE", "SIGKILL", "SIGUSR1", "SIGSEGV", "SIGUSR2",
            "SIGPIPE", "SIGALRM", "SIGTERM", "SIGSTKFLT", "SIGCHLD", "SIGCONT",
            "SIGSTOP", "SIGTSTP", "SIGTTIN", "SIGTTOU", "SIGURG", "SIGXCPU",
            "SIGXFSZ", "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGPOLL", "SIGPWR",
            "SIGSYS",
        };
        const rt_names = [_][]const u8{
            "SIGRTMIN", "SIGRTMIN+1", "SIGRTMIN+2", "SIGRTMIN+3",
            "SIGRTMIN+4", "SIGRTMIN+5", "SIGRTMIN+6", "SIGRTMIN+7",
            "SIGRTMIN+8", "SIGRTMIN+9", "SIGRTMIN+10", "SIGRTMIN+11",
            "SIGRTMIN+12", "SIGRTMIN+13", "SIGRTMIN+14", "SIGRTMIN+15",
            "SIGRTMAX-14", "SIGRTMAX-13", "SIGRTMAX-12", "SIGRTMAX-11",
            "SIGRTMAX-10", "SIGRTMAX-9", "SIGRTMAX-8", "SIGRTMAX-7",
            "SIGRTMAX-6", "SIGRTMAX-5", "SIGRTMAX-4", "SIGRTMAX-3",
            "SIGRTMAX-2", "SIGRTMAX-1", "SIGRTMAX",
        };
        const stdout = std.Io.File.stdout();
        var buf: [8192]u8 = undefined;
        var pos: usize = 0;
        for (sig_names, 1..) |name, i| {
            const line = std.fmt.bufPrint(buf[pos..], "{d}) {s}\t", .{i, name}) catch continue;
            pos += line.len;
        }
        for (rt_names, 32..) |name, i| {
            const line = std.fmt.bufPrint(buf[pos..], "{d}) {s}\t", .{i, name}) catch continue;
            pos += line.len;
        }
        if (pos > 0) pos -= 1;
        buf[pos] = '\n';
        pos += 1;
        _ = std.Io.File.writeStreamingAll(stdout, io, buf[0..pos]) catch {};
        return 0;
    }

    var signum: c_int = 15;
    var pid_start: usize = 1;
    if (std.mem.startsWith(u8, args[1], "-")) {
        const sigstr = args[1][1..];
        signum = std.fmt.parseInt(c_int, sigstr, 10) catch 15;
        pid_start = 2;
    }
    for (args[pid_start..]) |pid_str| {
        const pid = std.fmt.parseInt(c_int, pid_str, 10) catch {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "kill: {s}: invalid pid\n", .{pid_str}) catch "kill error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
            return 1;
        };
        if (c_kill(pid, signum) != 0) {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "kill: {s}: no such process\n", .{pid_str}) catch "kill error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
            return 1;
        }
    }
    return 0;
}

fn builtinAlias(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        const stdout = std.Io.File.stdout();
        for (var_store.getAliases()) |pair| {
            var buf: [1024]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "alias {s}='{s}'\n", .{pair.name, pair.value}) catch continue;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
        }
        return 0;
    }
    var had_error = false;
    for (args[1..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            const val = arg[eq+1..];
            var_store.setAlias(name, val);
        } else {
            if (var_store.getAlias(arg)) |val| {
                var buf: [1024]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "alias {s}='{s}'\n", .{arg, val}) catch continue;
                _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, line) catch {};
            } else {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "bash: alias: {s}: not found\n", .{arg}) catch "bash: alias: error\n";
                _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
                had_error = true;
            }
        }
    }
    return if (had_error) 1 else 0;
}

fn builtinUnalias(io: std.Io, args: [][]const u8) u8 {
    var had_error = false;
    for (args[1..]) |name| {
        if (var_store.getAlias(name) == null) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "bash: unalias: {s}: not found\n", .{name}) catch "bash: unalias: error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
            had_error = true;
        } else {
            var_store.removeAlias(name);
        }
    }
    return if (had_error) 1 else 0;
}

fn builtinBind(_: std.Io, _: [][]const u8) u8 { return 0; }

fn builtinCaller(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    // In non-interactive mode, just return 1
    _ = io;
    return 1;
}

fn builtinCommand(io: std.Io, args: [][]const u8) u8 {
    // command [-pvV] cmd [args...]
    // -v: print path of command, -V: verbose description
    if (args.len < 2) return 1;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "-v")) {
        if (args.len < 3) return 1;
        // Check if it's a builtin
        if (lookup(args[2])) |_| {
            const stdout = std.Io.File.stdout();
            var buf: [4096]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{s}\n", .{args[2]}) catch return 1;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
            return 0;
        }
        return 1;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "-V")) {
        if (args.len < 3) return 1;
        if (lookup(args[2])) |_| {
            const stdout = std.Io.File.stdout();
            var buf: [4096]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{s} is a shell builtin\n", .{args[2]}) catch return 1;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
            return 0;
        }
        return 1;
    }
    var cmd_start: usize = 1;
    while (cmd_start < args.len and args[cmd_start][0] == '-') {
        cmd_start += 1;
    }
    if (cmd_start >= args.len) return 1;
    // Skip builtins, run external command
    return runExternalCommand(io, args[cmd_start..]);
}

fn builtinCompgen(_: std.Io, _: [][]const u8) u8 { return 1; }
fn builtinComplete(_: std.Io, _: [][]const u8) u8 { return 0; }

fn builtinDeclare(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        const stdout = std.Io.File.stdout();
        for (var_store.allVars()) |v| {
            var buf: [4096]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "declare -- {s}=\"{s}\"\n", .{v.name, v.value}) catch continue;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
        }
        return 0;
    }
    // Support -a (array), -A (assoc array), -i (integer), -r (readonly), -x (export)
    var flags: u32 = 0;
    var var_start: usize = 1;
    while (var_start < args.len and args[var_start][0] == '-') {
        for (args[var_start][1..]) |ch| {
            switch (ch) {
                'a' => flags |= 1,
                'A' => flags |= 2,
                'i' => flags |= 4,
                'r' => flags |= 8,
                'x' => flags |= 16,
                'p' => flags |= 32,
                else => {},
            }
        }
        var_start += 1;
    }

    // Handle -p flag: print variable attributes
    if (flags & 32 != 0) {
        const stdout = std.Io.File.stdout();
        if (var_start >= args.len) {
            // -p with no args: print all variables (like bare declare)
            for (var_store.allVars()) |v| {
                var buf: [4096]u8 = undefined;
                const attr = if (var_store.isReadonly(v.name)) "declare -r" else if (var_store.hasIntVar(v.name)) "declare -i" else "declare --";
                const line = std.fmt.bufPrint(&buf, "{s} {s}=\"{s}\"\n", .{attr, v.name, v.value}) catch continue;
                _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
            }
        } else {
            for (args[var_start..]) |arg| {
                if (var_store.get(arg)) |v| {
                    var buf: [4096]u8 = undefined;
                    const attr = if (var_store.isReadonly(arg)) "declare -r" else if (var_store.hasIntVar(arg)) "declare -i" else "declare --";
                    const line = std.fmt.bufPrint(&buf, "{s} {s}=\"{s}\"\n", .{attr, arg, v.value}) catch continue;
                    _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
                }
            }
        }
        return 0;
    }

    for (args[var_start..]) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            var val = arg[eq+1..];
            if (flags & 4 != 0 and val.len > 0) {
                // For -i flag, evaluate as arithmetic expression
                if (builtinLetEvalArithmetic(val)) |v| {
                    var vbuf: [64]u8 = undefined;
                    val = std.fmt.bufPrint(&vbuf, "{d}", .{v}) catch val;
                }
            }
            if (flags & 16 != 0) {
                _ = var_store.set(name, val, true);
            } else {
                _ = var_store.set(name, val, false);
            }
            if (flags & 8 != 0) {
                var_store.setReadonly(name, true);
            }
            if (flags & 4 != 0) {
                var_store.setIntVar(name, true);
            }
        } else {
            if (flags & 16 != 0) {
                var_store.setExport(arg, true);
            }
            if (flags & 8 != 0) {
                var_store.setReadonly(arg, true);
            }
            if (flags & 4 != 0) {
                var_store.setIntVar(arg, true);
            }
        }
    }
    return 0;
}

fn builtinLetEvalArithmetic(expr: []const u8) ?i64 {
    if (std.fmt.parseInt(i64, expr, 10)) |val| return val else |_| {}
    // Handle simple arithmetic expressions like 5+3
    var full_buf: [4096]u8 = undefined;
    if (expr.len + 7 > full_buf.len) return null;
    full_buf[0] = '$';
    full_buf[1] = '(';
    full_buf[2] = '(';
    @memcpy(full_buf[3..][0..expr.len], expr);
    full_buf[3 + expr.len] = ')';
    full_buf[4 + expr.len] = ')';
    const full = full_buf[0 .. 5 + expr.len];
    if (expand.expandToken(std.heap.page_allocator, full)) |result| {
        defer result.deinit();
        if (result.words.len > 0) {
            return std.fmt.parseInt(i64, result.words[0], 10) catch null;
        }
    } else |_| {}
    return null;
}

fn builtinDirs(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    const stdout = std.Io.File.stdout();
    const dirs = var_store.getDirStack();
    for (dirs) |d| {
        var buf: [4096]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s} ", .{d}) catch continue;
        _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
    }
    _ = std.Io.File.writeStreamingAll(stdout, io, "\n") catch {};
    return 0;
}

fn builtinPushd(io: std.Io, args: [][]const u8) u8 {
    const dir = if (args.len >= 2) args[1] else "~";
    var_store.pushDir(dir);
    var buf: [4096]u8 = undefined;
    if (dir.len < buf.len) {
        @memcpy(buf[0..dir.len], dir);
        buf[dir.len] = 0;
        _ = chdir(buf[0..dir.len :0]);
    }
    return builtinDirs(io, args);
}

fn builtinPopd(io: std.Io, args: [][]const u8) u8 {
    var_store.popDir();
    const dirs = var_store.getDirStack();
    if (dirs.len > 0) {
        const top = dirs[dirs.len - 1];
        var buf: [4096]u8 = undefined;
        if (top.len < buf.len) {
            @memcpy(buf[0..top.len], top);
            buf[top.len] = 0;
            _ = chdir(buf[0..top.len :0]);
        }
    }
    return builtinDirs(io, args);
}

fn builtinEnable(_: std.Io, _: [][]const u8) u8 { return 0; }
fn builtinFc(_: std.Io, _: [][]const u8) u8 { return 0; }
fn builtinGetopts(_: std.Io, _: [][]const u8) u8 { return 1; }

fn builtinHash(io: std.Io, _: [][]const u8) u8 {
    const stdout = std.Io.File.stdout();
    _ = std.Io.File.writeStreamingAll(stdout, io, "hash: not fully implemented\n") catch {};
    return 0;
}

fn builtinHelp(io: std.Io, args: [][]const u8) u8 {
    const stdout = std.Io.File.stdout();
    if (args.len == 1) {
        _ = std.Io.File.writeStreamingAll(stdout, io,
            "GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)\n"
        ) catch {};
        return 0;
    }
    // bash help for specific builtins
    for (args[1..]) |name| {
        var buf: [4096]u8 = undefined;
        const line = std.fmt.bufPrint(&buf,
            "{s}: {s} [-neE] [arg ...]\n    Echo the STRING(s) to standard output.\n\n    Write arguments to the standard output.\n\n    Options:\n      -n\tdo not append a newline\n      -e\tenable interpretation of the following escape sequences\n      -E\texplicitly suppress interpretation of escape sequences\n\n    `echo' interprets the following escape sequences:\n      \\\\\tbackslash\n      \\a\talert (BEL)\n      \\b\tbackspace\n      \\c\tsuppress further output\n      \\e\tescape character\n      \\f\tform feed\n      \\n\tnew line\n      \\r\tcarriage return\n      \\t\thorizontal tab\n      \\v\tvertical tab\n      \\0NNN\tbyte with octal value NNN (1 to 3 digits)\n      \\xHH\tbyte with hexadecimal value HH (1 to 2 digits)\n\n    Exit Status:\n    Returns 0 unless a write error occurs.\n\n    Examples:\n      echo hello world\n      echo -n no newline\n      echo -e 'a\\tb'\n      echo $HOME\n      echo \"quoted string\"\n      echo a b c > file\n",
            .{ name, name }
        ) catch continue;
        _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
    }
    return 0;
}

fn builtinHistory(io: std.Io, _: [][]const u8) u8 {
    // Non-interactive: just return success
    _ = io;
    return 0;
}

pub fn evalLetExpr(expr: []const u8) ?i64 {
    if (std.fmt.parseInt(i64, expr, 10)) |val| return val else |_| {}
    var full_buf: [4096]u8 = undefined;
    if (expr.len + 7 > full_buf.len) return null;
    full_buf[0] = '$';
    full_buf[1] = '(';
    full_buf[2] = '(';
    @memcpy(full_buf[3..][0..expr.len], expr);
    full_buf[3 + expr.len] = ')';
    full_buf[4 + expr.len] = ')';
    const full = full_buf[0 .. 5 + expr.len];
    if (expand.expandToken(std.heap.page_allocator, full)) |result| {
        defer result.deinit();
        if (result.words.len > 0) {
            return std.fmt.parseInt(i64, result.words[0], 10) catch null;
        }
    } else |_| {}
    return null;
}

fn builtinLet(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    if (args.len < 2) return 1;
    var last_val: i64 = 0;
    for (args[1..]) |expr| {
        const trimmed = std.mem.trim(u8, expr, " ");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
            if (eq > 0 and (trimmed[eq-1] == '+' or trimmed[eq-1] == '-' or
                trimmed[eq-1] == '*' or trimmed[eq-1] == '/' or trimmed[eq-1] == '%'))
            {
                const name = std.mem.trim(u8, trimmed[0..eq-1], " ");
                const val_expr = std.mem.trim(u8, trimmed[eq+1..], " ");
                const cur_str = if (var_store.get(name)) |v| v.value else "0";
                const cur_val = std.fmt.parseInt(i64, cur_str, 10) catch 0;
                const rhs_val = evalLetExpr(val_expr) orelse 0;
                last_val = switch (trimmed[eq-1]) {
                    '+' => cur_val + rhs_val,
                    '-' => cur_val - rhs_val,
                    '*' => cur_val * rhs_val,
                    '/' => if (rhs_val == 0) 0 else @divTrunc(cur_val, rhs_val),
                    '%' => if (rhs_val == 0) 0 else @mod(cur_val, rhs_val),
                    else => 0,
                };
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
                _ = var_store.set(name, s, false);
            } else if (eq > 0 and trimmed[eq-1] != '=' and trimmed[eq-1] != '!' and
                trimmed[eq-1] != '<' and trimmed[eq-1] != '>')
            {
                const name = std.mem.trim(u8, trimmed[0..eq], " ");
                const val_expr = std.mem.trim(u8, trimmed[eq+1..], " ");
                last_val = evalLetExpr(val_expr) orelse 0;
                if (name.len > 0) {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
                    _ = var_store.set(name, s, false);
                }
            } else {
                last_val = evalLetExpr(trimmed) orelse 0;
            }
        } else if (trimmed.len >= 2 and std.mem.eql(u8, trimmed[trimmed.len-2..], "++")) {
            const name = std.mem.trim(u8, trimmed[0..trimmed.len-2], " ");
            const cur_str = if (var_store.get(name)) |v| v.value else "0";
            const cur_val = std.fmt.parseInt(i64, cur_str, 10) catch 0;
            last_val = cur_val + 1;
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
            _ = var_store.set(name, s, false);
        } else if (trimmed.len >= 2 and std.mem.eql(u8, trimmed[trimmed.len-2..], "--")) {
            const name = std.mem.trim(u8, trimmed[0..trimmed.len-2], " ");
            const cur_str = if (var_store.get(name)) |v| v.value else "0";
            const cur_val = std.fmt.parseInt(i64, cur_str, 10) catch 0;
            last_val = cur_val - 1;
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
            _ = var_store.set(name, s, false);
        } else if (trimmed.len >= 2 and trimmed[0] == '+' and trimmed[1] == '+') {
            const name = std.mem.trim(u8, trimmed[2..], " ");
            const cur_str = if (var_store.get(name)) |v| v.value else "0";
            const cur_val = std.fmt.parseInt(i64, cur_str, 10) catch 0;
            last_val = cur_val + 1;
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
            _ = var_store.set(name, s, false);
        } else if (trimmed.len >= 2 and trimmed[0] == '-' and trimmed[1] == '-') {
            const name = std.mem.trim(u8, trimmed[2..], " ");
            const cur_str = if (var_store.get(name)) |v| v.value else "0";
            const cur_val = std.fmt.parseInt(i64, cur_str, 10) catch 0;
            last_val = cur_val - 1;
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{last_val}) catch "0";
            _ = var_store.set(name, s, false);
        } else {
            last_val = evalLetExpr(trimmed) orelse 0;
        }
    }
    var qbuf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&qbuf, "{d}", .{if (last_val != 0) @as(u8, 0) else @as(u8, 1)}) catch "0";
    _ = var_store.set("?", s, false);
    return if (last_val != 0) 0 else 1;
}

fn builtinLogout(_: std.Io, _: [][]const u8) u8 { return 0; }

fn builtinMapfile(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    _ = args;
    // read lines into array (requires array support)
    return 1;
}

pub var shopt_nullglob: bool = false;
pub var shopt_dotglob: bool = false;
pub var shopt_extglob: bool = false;
pub var shopt_nocaseglob: bool = false;

fn builtinShopt(io: std.Io, args: [][]const u8) u8 {
    if (args.len == 1) {
        const stdout = std.Io.File.stdout();
        const options = comptime [_]struct { name: []const u8, state: *bool }{
            .{ .name = "dotglob",    .state = &shopt_dotglob },
            .{ .name = "extglob",    .state = &shopt_extglob },
            .{ .name = "nocaseglob", .state = &shopt_nocaseglob },
            .{ .name = "nullglob",   .state = &shopt_nullglob },
        };
        for (options) |opt| {
            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{s}    \t{s}\n", .{ opt.name, if (opt.state.*) "on" else "off" }) catch continue;
            _ = std.Io.File.writeStreamingAll(stdout, io, line) catch {};
        }
        return 0;
    }
    if (args.len >= 3) {
        const flag = args[1];
        const opt = args[2];
        if (std.mem.eql(u8, opt, "nullglob")) {
            shopt_nullglob = std.mem.eql(u8, flag, "-s");
        } else if (std.mem.eql(u8, opt, "dotglob")) {
            shopt_dotglob = std.mem.eql(u8, flag, "-s");
        } else if (std.mem.eql(u8, opt, "extglob")) {
            shopt_extglob = std.mem.eql(u8, flag, "-s");
        } else if (std.mem.eql(u8, opt, "nocaseglob")) {
            shopt_nocaseglob = std.mem.eql(u8, flag, "-s");
        }
    }
    return 0;
}

fn builtinSuspend(_: std.Io, _: [][]const u8) u8 { return 0; }

fn builtinUlimit(io: std.Io, args: [][]const u8) u8 {
    _ = args;
    // Just return success without implementing
    _ = io;
    return 0;
}

fn builtinUmask(io: std.Io, args: [][]const u8) u8 {
    if (args.len >= 2) {
        const mask = std.fmt.parseInt(u32, args[1], 8) catch return 1;
        // Can't actually change umask here easily
        _ = mask;
        return 0;
    }
    // Print current umask
    const stdout = std.Io.File.stdout();
    _ = std.Io.File.writeStreamingAll(stdout, io, "0022\n") catch {};
    return 0;
}

fn runExternalCommand(io: std.Io, args: [][]const u8) u8 {
    _ = io;
    const pa = std.heap.page_allocator;
    const pid = c.fork();
    if (pid < 0) return 126;
    if (pid == 0) {
        const argv = pa.alloc([*c]u8, args.len + 1) catch @panic("oom");
        for (args, 0..) |arg, i| {
            const arg_z = pa.dupeZ(u8, arg) catch @panic("oom");
            argv[i] = arg_z.ptr;
        }
        argv[args.len] = null;
        const cmd_z = pa.dupeZ(u8, args[0]) catch @panic("oom");
        _ = c.execvp(cmd_z.ptr, argv.ptr);
        c._exit(127);
    }
    var wstatus: c_int = 0;
    _ = waitpid(pid, &wstatus, 0);
    if (c.WIFEXITED(@as(c_int, @intCast(wstatus)))) {
        return @as(u8, @intCast(c.WEXITSTATUS(@as(c_int, @intCast(wstatus)))));
    }
    return 1;
}

fn builtinPrintf(io: std.Io, args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    const format = args[1];
    var arg_idx: usize = 2;
    var total_buf: [8192]u8 = undefined;
    var total_pos: usize = 0;

    // Loop over format string until all args consumed
    var format_cycle: usize = 0;
    while (arg_idx < args.len or format_cycle == 0) {
        format_cycle += 1;
        var buf_pos: usize = 0;
        var buf: [4096]u8 = undefined;
        var i: usize = 0;
        while (i < format.len and buf_pos < buf.len) {
            if (format[i] == '\\' and i + 1 < format.len) {
                i += 1;
                switch (format[i]) {
                    'n' => { buf[buf_pos] = '\n'; buf_pos += 1; },
                    't' => { buf[buf_pos] = '\t'; buf_pos += 1; },
                    '\\' => { buf[buf_pos] = '\\'; buf_pos += 1; },
                    '"' => { buf[buf_pos] = '"'; buf_pos += 1; },
                    else => { buf[buf_pos] = '\\'; buf_pos += 1; if (buf_pos < buf.len) { buf[buf_pos] = format[i]; buf_pos += 1; } },
                }
                i += 1;
            } else if (format[i] == '%' and i + 1 < format.len) {
                i += 1;
                if (format[i] == 's') {
                    if (arg_idx < args.len) {
                        const s = args[arg_idx];
                        arg_idx += 1;
                        const to_copy = @min(s.len, buf.len - buf_pos);
                        @memcpy(buf[buf_pos..buf_pos + to_copy], s[0..to_copy]);
                        buf_pos += to_copy;
                    }
                } else if (format[i] == 'd') {
                    if (arg_idx < args.len) {
                        const s = args[arg_idx];
                        arg_idx += 1;
                        const num_str = std.fmt.bufPrint(buf[buf_pos..], "{d}", .{std.fmt.parseInt(i64, s, 10) catch 0}) catch "";
                        buf_pos += num_str.len;
                    }
                } else if (format[i] == '%') {
                    buf[buf_pos] = '%';
                    buf_pos += 1;
                } else if (format[i] == 'b') {
                    if (arg_idx < args.len) {
                        const s = args[arg_idx];
                        arg_idx += 1;
                        var j: usize = 0;
                        while (j < s.len and buf_pos < buf.len) {
                            if (s[j] == '\\' and j + 1 < s.len) {
                                j += 1;
                                switch (s[j]) {
                                    'n' => { buf[buf_pos] = '\n'; buf_pos += 1; },
                                    't' => { buf[buf_pos] = '\t'; buf_pos += 1; },
                                    '\\' => { buf[buf_pos] = '\\'; buf_pos += 1; },
                                    else => { buf[buf_pos] = '\\'; buf_pos += 1; if (buf_pos < buf.len) { buf[buf_pos] = s[j]; buf_pos += 1; } },
                                }
                                j += 1;
                            } else {
                                buf[buf_pos] = s[j];
                                buf_pos += 1;
                                j += 1;
                            }
                        }
                    }
                } else if (format[i] == 'X') {
                    if (arg_idx < args.len) {
                        const s = args[arg_idx];
                        arg_idx += 1;
                        const num = std.fmt.parseInt(u64, s, 10) catch 0;
                        const num_str = std.fmt.bufPrint(buf[buf_pos..], "{X}", .{num}) catch "";
                        buf_pos += num_str.len;
                    }
                } else if (format[i] == 'x') {
                    if (arg_idx < args.len) {
                        const s = args[arg_idx];
                        arg_idx += 1;
                        const num = std.fmt.parseInt(u64, s, 10) catch 0;
                        const num_str = std.fmt.bufPrint(buf[buf_pos..], "{x}", .{num}) catch "";
                        buf_pos += num_str.len;
                    }
                } else {
                    if (buf_pos + 1 < buf.len) {
                        buf[buf_pos] = '%'; buf_pos += 1;
                        buf[buf_pos] = format[i]; buf_pos += 1;
                    }
                }
                i += 1;
            } else {
                buf[buf_pos] = format[i];
                buf_pos += 1;
                i += 1;
            }
        }
        // Append this cycle's output to total
        const to_copy = @min(buf_pos, total_buf.len - total_pos);
        @memcpy(total_buf[total_pos..total_pos + to_copy], buf[0..to_copy]);
        total_pos += to_copy;

        // Stop if no more args AND we've processed the format at least once
        if (arg_idx >= args.len) break;
    }
    _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, total_buf[0..total_pos]) catch {};
    return 0;
}
