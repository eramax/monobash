const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "xargs", .main = main };

pub fn main(args: [][]const u8) u8 {
    var max_args: usize = std.math.maxInt(usize);
    var max_chars: usize = std.math.maxInt(usize);
    var eof_str: ?[]const u8 = null;
    var repl_str: ?[]const u8 = null;
    var trace = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        var j: usize = 1;
        while (j < arg.len) {
            switch (arg[j]) {
                'n' => {
                    if (j + 1 < arg.len) { max_args = parseNum(arg[j+1..]); j = arg.len; }
                    else { i += 1; max_args = if (i < args.len) parseNum(args[i]) else max_args; }
                },
                's' => {
                    if (j + 1 < arg.len) { max_chars = parseNum(arg[j+1..]); j = arg.len; }
                    else { i += 1; max_chars = if (i < args.len) parseNum(args[i]) else max_chars; }
                },
                'E' => {
                    if (j + 1 < arg.len) { eof_str = arg[j+1..]; j = arg.len; }
                    else { i += 1; eof_str = if (i < args.len) args[i] else null; }
                },
                'e' => {
                    if (j + 1 < arg.len) { eof_str = arg[j+1..]; j = arg.len; }
                },
                'I' => {
                    if (j + 1 < arg.len) { repl_str = arg[j+1..]; j = arg.len; }
                    else { i += 1; repl_str = if (i < args.len) args[i] else null; }
                },
                't' => { trace = true; },
                else => return core.die(1, "xargs: unknown option -{c}\n", .{arg[j]}),
            }
            j += 1;
        }
        i += 1;
    }

    const user_cmd = args[i..];
    var words = std.ArrayListAligned([]const u8, null).empty;
    defer words.deinit(std.heap.page_allocator);

    var reader = core.LineReader.init(0);
    while (true) {
        const ent = reader.next();
        const line = ent orelse break;
        if (repl_str != null) {
            var trim: usize = 0;
            while (trim < line.len and (line[trim] == ' ' or line[trim] == '\t' or line[trim] == 0x0b)) trim += 1;
            if (trim >= line.len) continue;
            const trimmed = line[trim..];
            if (eof_str) |e| { if (std.mem.eql(u8, trimmed, e)) break; }
            words.append(std.heap.page_allocator, trimmed) catch break;
        } else {
            if (eof_str) |e| { if (std.mem.eql(u8, line, e)) break; }
            var start: usize = 0;
            while (start < line.len) {
                while (start < line.len and (line[start] == ' ' or line[start] == '\t')) start += 1;
                if (start >= line.len) break;
                var end = start + 1;
                while (end < line.len and !(line[end] == ' ' or line[end] == '\t')) end += 1;
                words.append(std.heap.page_allocator, line[start..end]) catch break;
                start = end;
            }
        }
    }

    if (words.items.len == 0) return 0;
    const alloc = std.heap.page_allocator;
    var rc: u8 = 0;

    if (repl_str) |repl| {
        for (words.items) |w| {
            var cmdv = std.ArrayListAligned([]const u8, null).empty;
            defer cmdv.deinit(alloc);
            if (user_cmd.len == 0) { cmdv.append(alloc, "echo") catch {}; }
            for (user_cmd) |c| { cmdv.append(alloc, c) catch {}; }
            if (user_cmd.len == 0) {
                cmdv.append(alloc, w) catch {};
            } else {
                for (user_cmd, 0..) |c, k| {
                    if (std.mem.indexOf(u8, c, repl) != null) {
                        var buf: [4096]u8 = undefined;
                        var pos: usize = 0;
                        var si: usize = 0;
                        while (std.mem.indexOf(u8, c[si..], repl)) |idx| {
                            @memcpy(buf[pos..][0..idx], c[si..][0..idx]);
                            pos += idx;
                            @memcpy(buf[pos..][0..w.len], w);
                            pos += w.len;
                            si += idx + repl.len;
                        }
                        @memcpy(buf[pos..][0..c.len - si], c[si..]);
                        pos += c.len - si;
                        cmdv.items[k] = alloc.dupe(u8, buf[0..pos]) catch continue;
                    }
                }
            }
            if (trace) logCmd(cmdv.items);
            const code = execCmd(cmdv.items);
            if (code) |c| { if (c != 0) rc = c; }
        }
    } else {
        var wi: usize = 0;
        while (wi < words.items.len) {
            var cmdv = std.ArrayListAligned([]const u8, null).empty;
            defer cmdv.deinit(alloc);
            if (user_cmd.len == 0) { cmdv.append(alloc, "echo") catch {}; }
            for (user_cmd) |c| { cmdv.append(alloc, c) catch {}; }
            var n: usize = 0;
            while (wi < words.items.len and n < max_args) {
                const w = words.items[wi];
                var clen: usize = 0;
                for (cmdv.items) |a| clen += a.len + 1;
                if (clen + w.len + 1 > max_chars) break;
                cmdv.append(alloc, w) catch {};
                n += 1;
                wi += 1;
            }
            if (trace) logCmd(cmdv.items);
            const code = execCmd(cmdv.items);
            if (code) |c| { if (c != 0) rc = c; }
        }
    }

    return rc;
}

fn parseNum(s: []const u8) usize {
    return std.fmt.parseInt(usize, s, 10) catch 0;
}

fn logCmd(argv: []const []const u8) void {
    for (argv, 0..) |a, idx| {
        if (idx > 0) core.writeAll(2, " ");
        core.writeAll(2, a);
    }
    core.writeAll(2, "\n");
}

fn execCmd(argv: []const []const u8) ?u8 {
    const pid = core.c.fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        const alloc = std.heap.page_allocator;
        var c_argv = alloc.alloc([*c]u8, argv.len + 1) catch std.process.exit(127);
        for (argv, 0..) |arg, k| {
            c_argv[k] = (alloc.dupeZ(u8, arg) catch std.process.exit(127)).ptr;
        }
        c_argv[argv.len] = null;
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }
    var ws: c_int = 0;
    while (core.c.waitpid(pid, &ws, 0) < 0) {}
    if (core.c.WIFEXITED(@as(c_int, @intCast(ws)))) {
        return @as(u8, @intCast(core.c.WEXITSTATUS(@as(c_int, @intCast(ws)))));
    }
    return 1;
}
