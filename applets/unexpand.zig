const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "unexpand", .main = main };
pub fn main(args: [][]const u8) u8 {
    var all: bool = false;
    var tabstop: usize = 8;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        for (args[i][1..]) |c| {
            switch (c) {
                'a' => all = true,
                't' => {
                    i += 1;
                    if (i >= args.len) return core.die(1, "unexpand: missing number after -t\n", .{});
                    tabstop = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "unexpand: invalid tabstop\n", .{});
                },
                else => return core.die(1, "unexpand: unknown flag '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);
    var buf: [1024 * 1024]u8 = undefined;
    var pos: usize = 0;
    var sc: usize = 0;
    var col: usize = 0;
    var sc_col: usize = 0;
    var leading = true;
    for (data) |ch| {
        if (ch == ' ') {
            if (sc == 0) sc_col = col;
            sc += 1;
            col += 1;
        } else {
            if (sc > 0) {
                flushSpaces(&buf, &pos, &sc, &sc_col, leading, all, tabstop);
                sc = 0;
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
    if (sc > 0) {
        flushSpaces(&buf, &pos, &sc, &sc_col, leading, all, tabstop);
    }
    core.writeAll(1, buf[0..pos]);
    return 0;
}
fn flushSpaces(buf: []u8, pos: *usize, count: *usize, col_start: *usize, leading: bool, all: bool, tabstop: usize) void {
    if (!leading and !all) {
        var j: usize = 0;
        while (j < count.*) : (j += 1) { buf[pos.*] = ' '; pos.* += 1; }
        return;
    }
    var remaining = count.*;
    var ccol = col_start.*;
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
