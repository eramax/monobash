const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "echo", .main = main };

fn writeEscaped(fd: c_int, s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            switch (s[i]) {
                'a' => core.writeAll(fd, "\x07"),
                'b' => core.writeAll(fd, "\x08"),
                'c' => return false,
                'f' => core.writeAll(fd, "\x0c"),
                'n' => core.writeAll(fd, "\n"),
                'r' => core.writeAll(fd, "\r"),
                't' => core.writeAll(fd, "\t"),
                'v' => core.writeAll(fd, "\x0b"),
                '\\' => core.writeAll(fd, "\\"),
                '0' => {
                    var val: u8 = 0;
                    var digits: usize = 0;
                    while (digits < 3 and i + 1 < s.len) {
                        const c = s[i + 1];
                        if (c >= '0' and c <= '7') {
                            val = val * 8 + (c - '0');
                            i += 1;
                            digits += 1;
                        } else break;
                    }
                    core.writeAll(fd, &.{val});
                },
                'x' => {
                    var val: u8 = 0;
                    var digits: usize = 0;
                    while (digits < 2 and i + 1 < s.len) {
                        const c = s[i + 1];
                        const d: u8 = switch (c) {
                            '0'...'9' => c - '0',
                            'a'...'f' => c - 'a' + 10,
                            'A'...'F' => c - 'A' + 10,
                            else => break,
                        };
                        val = val * 16 + d;
                        i += 1;
                        digits += 1;
                    }
                    if (digits > 0) {
                        core.writeAll(fd, &.{val});
                    } else {
                        core.writeAll(fd, "\\x");
                    }
                },
                '1'...'7' => {
                    var val: u8 = s[i] - '0';
                    var digits: usize = 1;
                    while (digits < 3 and i + 1 < s.len) {
                        const c = s[i + 1];
                        if (c >= '0' and c <= '7') {
                            val = val * 8 + (c - '0');
                            i += 1;
                            digits += 1;
                        } else break;
                    }
                    core.writeAll(fd, &.{val});
                },
                else => {
                    core.writeAll(fd, &.{'\\'});
                    core.writeAll(fd, s[i..i+1]);
                },
            }
            i += 1;
        } else {
            core.writeAll(fd, s[i..i+1]);
            i += 1;
        }
    }
    return true;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var no_newline = false;
    var enable_escapes = false;

    while (i < args.len and args[i].len > 1 and args[i][0] == '-') {
        const arg = args[i];
        var all_valid = true;
        for (arg[1..]) |c| {
            switch (c) {
                'n', 'e', 'E' => {},
                else => { all_valid = false; break; },
            }
        }
        if (all_valid) {
            for (arg[1..]) |c| {
                switch (c) {
                    'n' => no_newline = true,
                    'e' => enable_escapes = true,
                    'E' => enable_escapes = false,
                    else => {},
                }
            }
            i += 1;
        } else {
            break;
        }
    }

    var first = true;
    var continue_output = true;
    while (i < args.len) {
        if (!first) core.writeAll(1, " ");
        if (enable_escapes) {
            continue_output = writeEscaped(1, args[i]);
        } else {
            core.writeAll(1, args[i]);
        }
        first = false;
        i += 1;
        if (!continue_output) break;
    }
    if (continue_output and !no_newline) core.writeAll(1, "\n");
    return 0;
}
