const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "xxd", .main = main };

fn hexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn isxdigit(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

fn skipWS(s: []const u8) []const u8 {
    for (s, 0..) |c, i| {
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') return s[i..];
    }
    return s[s.len..];
}

fn reverseMode(data: []const u8, plain: bool, alloc: std.mem.Allocator, out: *std.ArrayList(u8)) void {
    var pos: usize = 0;
    while (pos < data.len) {
        var line_end = pos;
        while (line_end < data.len and data[line_end] != '\n') : (line_end += 1) {}
        const line = data[pos..line_end];
        pos = if (line_end < data.len) line_end + 1 else line_end;
        if (line.len == 0) continue;

        var p = line;

        if (!plain) {
            p = skipWS(p);
            var addr_end: usize = 0;
            while (addr_end < p.len and isxdigit(p[addr_end])) : (addr_end += 1) {}
            if (addr_end > 0) p = p[addr_end..];
            if (p.len > 0 and p[0] == ':') p = p[1..];
        }

        var badchar: u32 = 0;
        while (p.len > 0) {
            if (plain) p = skipWS(p);
            if (p.len == 0) break;
            const c1 = p[0];
            p = p[1..];

            const d1 = hexDigit(c1);
            if (d1) |d| {
                var val = d << 4;

                if (plain) p = skipWS(p);
                if (p.len == 0) break;
                const c2 = p[0];
                p = p[1..];

                if (hexDigit(c2)) |d2| {
                    val |= d2;
                    out.append(alloc, val) catch {};
                    badchar = 0;
                } else if (c2 != 0) {
                    while (p.len > 0 and !isxdigit(p[0])) {
                        if (p[0] == 0) {
                            p = p[1..];
                            break;
                        }
                        p = p[1..];
                    }
                }
            } else {
                if (c1 == 0 or badchar > 0) break;
                badchar += 1;
            }
        }
    }
}

fn plainDump(data: []const u8) void {
    const COLS: usize = 30;
    var lbuf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) {
        var j: usize = 0;
        var pos: usize = 0;
        while (j < COLS and i + j < data.len) : (j += 1) {
            const hex = std.fmt.bufPrint(lbuf[pos..], "{x:0>2}", .{data[i + j]}) catch "";
            pos += hex.len;
        }
        lbuf[pos] = '\n';
        core.writeAll(1, lbuf[0..pos + 1]);
        i += j;
    }
}

pub fn main(args: [][]const u8) u8 {
    var opt_p = false;
    var opt_r = false;
    var ai: usize = 1;
    while (ai < args.len) {
        const arg = args[ai];
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-p")) {
                opt_p = true;
            } else if (std.mem.eql(u8, arg, "-r")) {
                opt_r = true;
            } else if (std.mem.eql(u8, arg, "--")) {
                ai += 1;
                break;
            } else {
                return core.die(1, "xxd: unknown option: {s}\n", .{arg});
            }
        } else break;
        ai += 1;
    }

    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024 * 16) catch return 1;
    defer alloc.free(data);

    if (opt_r) {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(alloc);
        reverseMode(data, opt_p, alloc, &out);
        core.writeAll(1, out.items);
    } else {
        plainDump(data);
    }

    return 0;
}
