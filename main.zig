const std = @import("std");
const parser = @import("parser.zig");
const var_store = @import("var.zig");
const expand = @import("expand.zig");
const executor = @import("executor.zig");
const builtins = @import("builtins.zig");
const applets = @import("applets.zig");
const core = @import("applets/core.zig");
const history_mod = @import("history.zig");
const cimport = @import("cimport.zig");
const c = cimport.c;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const prog_name = std.fs.path.basename(args[0]);
    const is_shell = std.mem.indexOf(u8, prog_name, "monobash") != null or
        std.mem.eql(u8, prog_name, "bash") or
        std.mem.eql(u8, prog_name, "sh");

    if (!is_shell) {
        std.debug.print("bash: {s}: command not found\n", .{prog_name});
        std.process.exit(127);
    }

    parser.init();
    defer parser.deinit();

    var_store.init(arena);
    defer var_store.deinit();

    executor.init(arena);

    _ = core.initUring(64) catch {};

    if (args.len >= 3 and std.mem.eql(u8, args[1], "-c")) {
        var_store.command_flag = true;
        const cmd = args[2];
        const tree = parser.parseString(cmd) orelse {
            const msg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(2);
        };
        defer parser.treeDelete(tree);
        const status = executor.exec(init.io, tree, cmd);
        std.process.exit(status);
    }

    if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "-")) {
        const path = args[1];
        const content = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), init.io, path, arena, .unlimited) catch {
            const msg = std.fmt.allocPrint(arena, "bash: {s}: No such file or directory\n", .{path}) catch unreachable;
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(127);
        };
        var_store.setPositional(arena, &.{});
        _ = var_store.set("0", path, false);
        const script = if (std.mem.startsWith(u8, content, "#!"))
            (std.mem.indexOfScalar(u8, content, '\n') orelse return) + 1
        else
            0;
        const body = content[script..];
        const body_z = try arena.dupeZ(u8, body);
        const tree = parser.parseString(body_z) orelse {
            const msg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(2);
        };
        defer parser.treeDelete(tree);
        const status = executor.exec(init.io, tree, body);
        std.process.exit(status);
    }

    // Interactive / REPL mode
    var_store.interactive = true;

    var last_status: u8 = 0;

    // History
    var_store.setupHistory(arena);
    const hist_size_str = if (var_store.get("HISTSIZE")) |v| v.value else "1000";
    const hist_size = std.fmt.parseUnsigned(usize, hist_size_str, 10) catch 1000;
    const histfile = if (var_store.get("HISTFILE")) |v| v.value else "";
    var history = history_mod.History.init(arena, hist_size);
    history_mod.instance = &history;
    if (histfile.len > 0) history.load(histfile);

    // Terminal raw mode setup
    var orig_termios: c.struct_termios = undefined;
    const have_terminal = c.isatty(c.STDIN_FILENO) == 1;
    if (have_terminal) {
        _ = c.tcgetattr(c.STDIN_FILENO, &orig_termios);
    }
    defer {
        if (histfile.len > 0) history.save(histfile);
        if (have_terminal) _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios);
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, "\n") catch {};
    }

    while (true) {
        const prompt = if (last_status == 0) "monobash$ " else "monobash! ";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, prompt) catch break;

        const line_or_null = if (have_terminal) readLineRaw(arena, &history) else readLineSimple(arena);
        const line = line_or_null orelse break;
        defer arena.free(line);

        if (line.len == 0) continue;

        history.add(line);
        if (histfile.len > 0) history.append(histfile, line);

        const line_z = arena.dupeZ(u8, line) catch continue;
        const tree = parser.parseString(line_z) orelse {
            const errmsg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, errmsg) catch {};
            continue;
        };
        defer parser.treeDelete(tree);
        last_status = executor.exec(init.io, tree, line_z);
    }
}

fn readLineSimple(arena: std.mem.Allocator) ?[]const u8 {
    var line_buf: [4096]u8 = undefined;
    if (c.fgets(&line_buf, @as(c_int, @intCast(line_buf.len)), c.stdin)) |_| {
        const raw = std.mem.sliceTo(&line_buf, 0);
        if (raw.len == 0) return null;
        var end = raw.len;
        while (end > 0 and (raw[end-1] == ' ' or raw[end-1] == '\t' or raw[end-1] == '\r' or raw[end-1] == '\n')) end -= 1;
        const trimmed = raw[0..end];
        return arena.dupe(u8, trimmed) catch null;
    }
    return null;
}

fn readLineRaw(arena: std.mem.Allocator, history: *history_mod.History) ?[]const u8 {
    // Switch to raw mode
    var raw: c.struct_termios = undefined;
    _ = c.tcgetattr(c.STDIN_FILENO, &raw);
    _ = c.cfmakeraw(&raw);
    _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw);

    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;

    while (true) {
        var ch: u8 = undefined;
        const n = c.read(c.STDIN_FILENO, &ch, 1);
        if (n <= 0) break;

        switch (ch) {
            3 => { // Ctrl-C
                len = 0;
                cursor = 0;
                _ = c.write(c.STDOUT_FILENO, "\n", 1);
                break;
            },
            4 => { // Ctrl-D
                if (len == 0) {
                    _ = c.write(c.STDOUT_FILENO, "\n", 1);
                    break;
                }
            },
            8, 127 => { // Backspace
                if (cursor > 0) {
                    cursor -= 1;
                    for (cursor..len - 1) |j| buf[j] = buf[j + 1];
                    len -= 1;
                    _ = c.write(c.STDOUT_FILENO, "\x08", 1);
                    redrawLine(buf[0..len], cursor);
                }
            },
            10, 13 => { // Enter
                _ = c.write(c.STDOUT_FILENO, "\n", 1);
                break;
            },
            27 => { // Escape sequence
                var seq: [2]u8 = undefined;
                if (c.read(c.STDIN_FILENO, &seq, 2) != 2) {
                    // Just enter escape char
                    if (len < buf.len) { for (len..0) |_| buf[len] = ch; len += 1; cursor += 1; redrawLine(buf[0..len], cursor); }
                    continue;
                }
                if (seq[0] == '[') {
                    switch (seq[1]) {
                        'A' => { // Up arrow
                            if (history.getPrev()) |h| {
                                len = @min(h.len, buf.len);
                                @memcpy(buf[0..len], h[0..len]);
                                cursor = len;
                                redrawLine(buf[0..len], cursor);
                            }
                        },
                        'B' => { // Down arrow
                            if (history.getNext()) |h| {
                                len = @min(h.len, buf.len);
                                @memcpy(buf[0..len], h[0..len]);
                                cursor = len;
                            } else {
                                len = 0;
                                cursor = 0;
                            }
                            redrawLine(buf[0..len], cursor);
                        },
                        'C' => { // Right arrow
                            if (cursor < len) {
                                cursor += 1;
                                _ = c.write(c.STDOUT_FILENO, "\x1b[C", 3);
                            }
                        },
                        'D' => { // Left arrow
                            if (cursor > 0) {
                                cursor -= 1;
                                _ = c.write(c.STDOUT_FILENO, "\x1b[D", 3);
                            }
                        },
                        else => {},
                    }
                }
            },
            21 => { // Ctrl-U: kill line
                len = 0;
                cursor = 0;
                _ = c.write(c.STDOUT_FILENO, "\x1b[K", 3);
            },
            11 => { // Ctrl-K: kill to end
                len = cursor;
                _ = c.write(c.STDOUT_FILENO, "\x1b[J", 3);
            },
            1 => { // Ctrl-A: home
                cursor = 0;
                _ = c.write(c.STDOUT_FILENO, "\x1b[G", 3);
            },
            5 => { // Ctrl-E: end
                cursor = len;
                redrawLine(buf[0..len], cursor);
            },
            23 => { // Ctrl-W: delete word backward
                if (cursor > 0) {
                    const end = cursor;
                    cursor -= 1;
                    while (cursor > 0 and buf[cursor] == ' ') cursor -= 1;
                    while (cursor > 0 and buf[cursor - 1] != ' ') cursor -= 1;
                    const leftover = len - end;
                    if (leftover > 0) @memcpy(buf[cursor..][0..leftover], buf[end..][0..leftover]);
                    len -= end - cursor;
                    redrawLine(buf[0..len], cursor);
                }
            },
            else => {
                if (ch >= 32 and len < buf.len) {
                    // Insert character at cursor position
                    if (cursor < len) {
                        var j = len;
                        while (j > cursor) {
                            buf[j] = buf[j - 1];
                            j -= 1;
                        }
                    }
                    buf[cursor] = ch;
                    cursor += 1;
                    len += 1;
                    redrawLine(buf[0..len], cursor);
                }
            },
        }

        if (ch == 10 or ch == 13) break;
    }

    // Restore cooked mode
    var restore: c.struct_termios = undefined;
    _ = c.tcgetattr(c.STDIN_FILENO, &restore);
    _ = c.cfmakeraw(&restore);
    // Actually restore from the saved termios - done by the 'defer' in main

    if (len == 0) return arena.dupe(u8, "") catch null;
    return arena.dupe(u8, buf[0..len]) catch null;
}

fn redrawLine(line: []const u8, cursor: usize) void {
    _ = c.write(c.STDOUT_FILENO, "\x1b[2K\r", 5); // Clear line, carriage return
    _ = c.write(c.STDOUT_FILENO, line.ptr, line.len);
    const right = line.len - cursor;
    if (right > 0) {
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "\x1b[{}D", .{right}) catch return;
        _ = c.write(c.STDOUT_FILENO, s.ptr, s.len);
    }
}
