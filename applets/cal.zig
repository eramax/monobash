const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "cal", .main = main };
pub fn main(args: [][]const u8) u8 {
    var year: usize = 0;
    var month: usize = 0;
    if (args.len == 1) {
        var t: core.c.time_t = undefined;
        _ = core.c.time(&t);
        const tm = core.c.localtime(&t);
        month = @intCast(tm.*.tm_mon + 1);
        year = @intCast(tm.*.tm_year + 1900);
    } else if (args.len == 2) {
        year = std.fmt.parseInt(usize, args[1], 10) catch return core.die(1, "cal: invalid year\n", .{});
        if (year > 9999) return core.die(1, "cal: year out of range\n", .{});
    } else if (args.len == 3) {
        month = std.fmt.parseInt(usize, args[1], 10) catch return core.die(1, "cal: invalid month\n", .{});
        if (month < 1 or month > 12) return core.die(1, "cal: invalid month\n", .{});
        year = std.fmt.parseInt(usize, args[2], 10) catch return core.die(1, "cal: invalid year\n", .{});
        if (year > 9999) return core.die(1, "cal: year out of range\n", .{});
    }
    if (month == 0) printYear(year) else printMonth(month, year);
    return 0;
}
fn dow(y: usize, m: usize, d: usize) usize {
    var yy = y;
    if (m < 3) yy -|= 1;
    const t = [_]usize{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    return (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7;
}
fn dim(m: usize, y: usize) usize {
    return switch (m) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) 29 else 28,
        else => 0,
    };
}
const MONTHS = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
fn printMonth(m: usize, y: usize) void {
    var buf: [128]u8 = undefined;
    const hdr = std.fmt.bufPrint(&buf, "{s} {d}", .{ MONTHS[m - 1], y }) catch "";
    var i: usize = 0;
    while (i < (20 -| hdr.len) / 2) { core.writeAll(1, " "); i += 1; }
    core.writeAll(1, hdr);
    core.writeAll(1, "\nSu Mo Tu We Th Fr Sa\n");
    const days = dim(m, y);
    const start = dow(y, m, 1);
    var j: usize = 0;
    while (j < start) { core.writeAll(1, "   "); j += 1; }
    var d: usize = 1;
    while (d <= days) {
        const s = std.fmt.bufPrint(&buf, "{d:>2}", .{d}) catch "";
        core.writeAll(1, s);
        if ((start + d) % 7 == 0) {
            core.writeAll(1, "\n");
        } else if (d < days) {
            core.writeAll(1, " ");
        }
        d += 1;
    }
    if ((start + days) % 7 != 0) core.writeAll(1, "\n");
}
fn printYear(y: usize) void {
    var buf: [128]u8 = undefined;
    const hdr = std.fmt.bufPrint(&buf, "{d}", .{y}) catch "";
    var i: usize = 0;
    while (i < (64 -| hdr.len) / 2) { core.writeAll(1, " "); i += 1; }
    core.writeAll(1, hdr);
    core.writeAll(1, "\n\n");
    var row: usize = 0;
    while (row < 4) {
        var col: usize = 0;
        while (col < 3) {
            const m = row * 3 + col + 1;
            const hdr2 = std.fmt.bufPrint(&buf, "{s}", .{MONTHS[m - 1]}) catch "";
            var pad: usize = 0;
            if (hdr2.len < 20) pad = (20 - hdr2.len) / 2;
            var j: usize = 0;
            while (j < pad) { core.writeAll(1, " "); j += 1; }
            core.writeAll(1, hdr2);
            j = 0;
            while (j < 20 - pad - hdr2.len) { core.writeAll(1, " "); j += 1; }
            core.writeAll(1, "  ");
            col += 1;
        }
        core.writeAll(1, "\n");
        col = 0;
        while (col < 3) {
            core.writeAll(1, "Su Mo Tu We Th Fr Sa  ");
            col += 1;
        }
        core.writeAll(1, "\n");
        var day_cells = [_]usize{1, 1, 1};
        const starts = [_]usize{
            dow(y, row * 3 + 1, 1),
            dow(y, row * 3 + 2, 1),
            dow(y, row * 3 + 3, 1),
        };
        const dims = [_]usize{
            dim(row * 3 + 1, y),
            dim(row * 3 + 2, y),
            dim(row * 3 + 3, y),
        };
        var week: usize = 0;
        while (week < 6) {
            var any = false;
            col = 0;
            while (col < 3) {
                var d = day_cells[col];
                const start_col = starts[col];
                const max = dims[col];
                var k: usize = 0;
                while (k < 7) {
                    if (week == 0 and k < start_col) {
                        core.writeAll(1, "   ");
                    } else if (d <= max) {
                        const s = std.fmt.bufPrint(&buf, "{d:>2}", .{d}) catch "";
                        core.writeAll(1, s);
                        d += 1;
                        any = true;
                    } else {
                        core.writeAll(1, "   ");
                    }
                    if (k < 6) core.writeAll(1, " ");
                    k += 1;
                }
                core.writeAll(1, "  ");
                day_cells[col] = d;
                col += 1;
            }
            core.writeAll(1, "\n");
            if (!any) break;
            week += 1;
        }
        row += 1;
    }
}
