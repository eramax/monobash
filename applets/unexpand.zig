const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "unexpand", .main = main };
pub fn main(args: [][]const u8) u8 {
    var opt_a = false;
    var opt_f = false;
    var opt_t = false;
    var tabstop: usize = 8;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--first-only")) {
            opt_f = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else if (arg.len > 2 and arg[0] == '-' and arg[1] == 't') {
            const val = arg[2..];
            tabstop = std.fmt.parseUnsigned(usize, val, 10) catch return core.die(1, "unexpand: invalid tabstop\n", .{});
            opt_t = true;
        } else {
            var j: usize = 1;
            while (j < arg.len) {
                switch (arg[j]) {
                    'a' => opt_a = true,
                    'f' => opt_f = true,
                    't' => {
                        if (j + 1 < arg.len) {
                            tabstop = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(1, "unexpand: invalid tabstop\n", .{});
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(1, "unexpand: missing number after -t\n", .{});
                            tabstop = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "unexpand: invalid tabstop\n", .{});
                        }
                        opt_t = true;
                    },
                    else => return core.die(1, "unexpand: unknown flag '{c}'\n", .{arg[j]}),
                }
                j += 1;
            }
        }
        i += 1;
    }
    const all = opt_a or (!opt_f and opt_t);
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);
    var buf: [1024 * 1024]u8 = undefined;
    var pos: usize = 0;
    var col: usize = 0;
    var leading = true;
    var ws_idx: usize = 0;
    var ws_cols: usize = 0;
    var ws_start_col: usize = 0;
    var ws_has_tab = false;
    for (data, 0..) |ch, idx| {
        if (ch == ' ' or ch == '\t') {
            if (ws_idx == 0) {
                ws_start_col = col;
                ws_cols = 0;
                ws_has_tab = false;
            }
            ws_idx += 1;
            if (ch == '\t') {
                ws_has_tab = true;
                const adv = tabstop - (col % tabstop);
                ws_cols += adv;
                col += adv;
            } else {
                ws_cols += 1;
                col += 1;
            }
        } else {
            if (ws_idx > 0) {
                if (leading or all or ws_has_tab) {
                    flushSpaces(&buf, &pos, ws_cols, ws_start_col, tabstop);
                } else {
                    for (data[idx - ws_idx .. idx]) |wc| { buf[pos] = wc; pos += 1; }
                }
                ws_idx = 0;
            }
            buf[pos] = ch;
            pos += 1;
            col += 1;
            if (ch == '\n') {
                col = 0;
                leading = true;
            } else {
                leading = false;
            }
        }
    }
    if (ws_idx > 0) {
        if (leading or all or ws_has_tab) {
            flushSpaces(&buf, &pos, ws_cols, ws_start_col, tabstop);
        } else {
            for (data[data.len - ws_idx ..]) |wc| { buf[pos] = wc; pos += 1; }
        }
    }
    core.writeAll(1, buf[0..pos]);
    return 0;
}
fn flushSpaces(buf: []u8, pos: *usize, count: usize, col_start: usize, tabstop: usize) void {
    var remaining = count;
    var ccol = col_start;
    const to_bound = tabstop - (ccol % tabstop);
    if (to_bound < tabstop and to_bound > 0 and remaining >= to_bound) {
        buf[pos.*] = '\t';
        pos.* += 1;
        remaining -= to_bound;
        ccol += to_bound;
    }
    if (ccol % tabstop == 0) {
        const tabs = remaining / tabstop;
        var ti: usize = 0;
        while (ti < tabs) : (ti += 1) { buf[pos.*] = '\t'; pos.* += 1; }
        remaining %= tabstop;
    }
    var si: usize = 0;
    while (si < remaining) : (si += 1) { buf[pos.*] = ' '; pos.* += 1; }
}
