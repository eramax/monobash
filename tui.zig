const std = @import("std");
const cimport = @import("cimport.zig");
const c = cimport.c;
const history_mod = @import("history.zig");

pub fn readLineSimple(arena: std.mem.Allocator) ?[]const u8 {
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

pub const Terminal = struct {
    orig_termios: c.struct_termios,
    have_terminal: bool,

    pub fn init() Terminal {
        var t = Terminal{ .orig_termios = undefined, .have_terminal = false };
        if (c.isatty(c.STDIN_FILENO) == 1) {
            t.have_terminal = true;
            _ = c.tcgetattr(c.STDIN_FILENO, &t.orig_termios);
        }
        return t;
    }

    pub fn deinit(self: *Terminal) void {
        if (self.have_terminal) {
            _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.orig_termios);
        }
    }

    pub fn enterRaw(self: *Terminal) void {
        if (!self.have_terminal) return;
        var raw: c.struct_termios = undefined;
        _ = c.tcgetattr(c.STDIN_FILENO, &raw);
        _ = c.cfmakeraw(&raw);
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw);
    }

    pub fn exitRaw(self: *Terminal) void {
        if (!self.have_terminal) return;
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.orig_termios);
    }
};

pub fn readLine(arena: std.mem.Allocator, history: *history_mod.History, prompt: []const u8, term: *Terminal) ?[]const u8 {
    if (!term.have_terminal) {
        return readLineSimple(arena);
    }

    term.enterRaw();
    defer term.exitRaw();
    _ = c.write(c.STDOUT_FILENO, prompt.ptr, prompt.len);

    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var eof: bool = false;

    while (true) {
        var ch: u8 = undefined;
        const n = c.read(c.STDIN_FILENO, &ch, 1);
        if (n <= 0) { eof = true; break; }

        switch (ch) {
            3 => {
                len = 0;
                cursor = 0;
                _ = c.write(c.STDOUT_FILENO, "\r\n", 2);
                break;
            },
            4 => {
                if (len == 0) {
                    _ = c.write(c.STDOUT_FILENO, "\r\n", 2);
                    eof = true;
                    break;
                }
            },
            8, 127 => {
                if (cursor > 0) {
                    cursor -= 1;
                    for (cursor..len - 1) |j| buf[j] = buf[j + 1];
                    len -= 1;
                    _ = c.write(c.STDOUT_FILENO, "\x08", 1);
                    for (cursor..len) |_| _ = c.write(c.STDOUT_FILENO, &[_]u8{buf[cursor]}, 1);
                    _ = c.write(c.STDOUT_FILENO, " \x08", 2);
                    if (cursor < len) {
                        var move: [16]u8 = undefined;
                        const s = std.fmt.bufPrint(&move, "\x1b[{}D", .{len - cursor}) catch unreachable;
                        _ = c.write(c.STDOUT_FILENO, s.ptr, s.len);
                    }
                }
            },
            10, 13 => {
                _ = c.write(c.STDOUT_FILENO, "\r\n", 2);
            },
            27 => {
                var seq: [2]u8 = undefined;
                if (c.read(c.STDIN_FILENO, &seq, 2) != 2) continue;
                if (seq[0] == '[') {
                    switch (seq[1]) {
                        'A' => {
                            if (history.getPrev()) |h| {
                                len = @min(h.len, buf.len);
                                @memcpy(buf[0..len], h[0..len]);
                                cursor = len;
                                redrawAll(buf[0..len], prompt);
                            }
                        },
                        'B' => {
                            if (history.getNext()) |h| {
                                len = @min(h.len, buf.len);
                                @memcpy(buf[0..len], h[0..len]);
                                cursor = len;
                            } else {
                                len = 0;
                                cursor = 0;
                            }
                            redrawAll(buf[0..len], prompt);
                        },
                        'C' => {
                            if (cursor < len) {
                                cursor += 1;
                                _ = c.write(c.STDOUT_FILENO, "\x1b[C", 3);
                            }
                        },
                        'D' => {
                            if (cursor > 0) {
                                cursor -= 1;
                                _ = c.write(c.STDOUT_FILENO, "\x1b[D", 3);
                            }
                        },
                        else => {},
                    }
                }
            },
            21 => {
                len = 0;
                cursor = 0;
                redrawAll(buf[0..len], prompt);
            },
            11 => {
                len = cursor;
                _ = c.write(c.STDOUT_FILENO, "\x1b[J", 3);
            },
            1 => {
                cursor = 0;
                var move: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&move, "\x1b[{}G", .{prompt.len + 1}) catch unreachable;
                _ = c.write(c.STDOUT_FILENO, s.ptr, s.len);
            },
            5 => {
                cursor = len;
                redrawAll(buf[0..len], prompt);
            },
            23 => {
                if (cursor > 0) {
                    const end = cursor;
                    cursor -= 1;
                    while (cursor > 0 and buf[cursor] == ' ') cursor -= 1;
                    while (cursor > 0 and buf[cursor - 1] != ' ') cursor -= 1;
                    const leftover = len - end;
                    if (leftover > 0) @memcpy(buf[cursor..][0..leftover], buf[end..][0..leftover]);
                    len -= end - cursor;
                    redrawAll(buf[0..len], prompt);
                }
            },
            else => {
                if (ch >= 32 and len < buf.len) {
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
                    if (cursor == len) {
                        _ = c.write(c.STDOUT_FILENO, &[_]u8{ch}, 1);
                    } else {
                        _ = c.write(c.STDOUT_FILENO, &[_]u8{ch}, 1);
                        for (cursor..len) |j| _ = c.write(c.STDOUT_FILENO, &[_]u8{buf[j]}, 1);
                        var move: [16]u8 = undefined;
                        const s = std.fmt.bufPrint(&move, "\x1b[{}D", .{len - cursor}) catch unreachable;
                        _ = c.write(c.STDOUT_FILENO, s.ptr, s.len);
                    }
                }
            },
        }

        if (ch == 10 or ch == 13) break;
    }

    if (eof) return null;
    if (len == 0) return arena.dupe(u8, "") catch null;
    return arena.dupe(u8, buf[0..len]) catch null;
}

fn redrawAll(line: []const u8, prompt: []const u8) void {
    _ = c.write(c.STDOUT_FILENO, "\r\x1b[2K", 5);
    _ = c.write(c.STDOUT_FILENO, prompt.ptr, prompt.len);
    _ = c.write(c.STDOUT_FILENO, line.ptr, line.len);
}
