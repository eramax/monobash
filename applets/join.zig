const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "join", .main = main };
pub fn main(args: [][]const u8) u8 {
    var sep: u8 = ' ';
    var join_field: usize = 0;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-t")) {
            i += 1;
            if (i >= args.len) return core.die(1, "join: missing arg after -t\n", .{});
            sep = if (args[i].len > 0) args[i][0] else ' ';
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-j")) {
            i += 1;
            if (i >= args.len) return core.die(1, "join: missing arg after -j\n", .{});
            const n = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "join: invalid -j value\n", .{});
            join_field = if (n > 0) n - 1 else 0;
            i += 1;
        } else return core.die(1, "join: unknown option: {s}\n", .{args[i]});
    }
    const files = args[i..];
    if (files.len < 2) return core.die(1, "join: need two files\n", .{});
    const alloc = std.heap.page_allocator;
    const fd1 = core.openReadName(files[0]) orelse return core.die(1, "join: cannot open '{s}'\n", .{files[0]});
    const d1 = core.readAll(alloc, fd1, 1024 * 1024) catch return 1;
    _ = core.c.close(fd1);
    const fd2 = core.openReadName(files[1]) orelse {
        alloc.free(d1);
        return core.die(1, "join: cannot open '{s}'\n", .{files[1]});
    };
    const d2 = core.readAll(alloc, fd2, 1024 * 1024) catch return 1;
    _ = core.c.close(fd2);
    defer { alloc.free(d1); alloc.free(d2); }

    var n: [2]usize = .{ 1, 1 };
    for (d1) |c| { if (c == '\n') n[0] += 1; }
    if (d1.len > 0 and d1[d1.len - 1] == '\n') n[0] -= 1;
    for (d2) |c| { if (c == '\n') n[1] += 1; }
    if (d2.len > 0 and d2[d2.len - 1] == '\n') n[1] -= 1;

    const l1 = alloc.alloc([]const u8, n[0]) catch return 1;
    const l2 = alloc.alloc([]const u8, n[1]) catch return 1;
    defer { alloc.free(l1); alloc.free(l2); }

    var idx: usize = 0;
    var start: usize = 0;
    for (d1, 0..) |ch, pos| {
        if (ch == '\n') { if (idx < n[0]) l1[idx] = d1[start..pos]; idx += 1; start = pos + 1; }
    }
    if (start < d1.len and idx < n[0]) l1[idx] = d1[start..];

    idx = 0;
    start = 0;
    for (d2, 0..) |ch, pos| {
        if (ch == '\n') { if (idx < n[1]) l2[idx] = d2[start..pos]; idx += 1; start = pos + 1; }
    }
    if (start < d2.len and idx < n[1]) l2[idx] = d2[start..];

    for (l1) |line1| {
        const f1 = getField(line1, sep, join_field);
        for (l2) |line2| {
            const f2 = getField(line2, sep, join_field);
            if (std.mem.eql(u8, f1, f2)) {
                core.writeAll(1, f1);
                const r1 = restOf(line1, sep, join_field);
                if (r1.len > 0) { core.writeAll(1, &[_]u8{sep}); core.writeAll(1, r1); }
                core.writeAll(1, &[_]u8{sep});
                core.writeAll(1, line2);
                core.writeAll(1, "\n");
            }
        }
    }
    return 0;
}
fn getField(line: []const u8, sep: u8, idx: usize) []const u8 {
    var fi: usize = 0;
    var s: usize = 0;
    for (line, 0..) |ch, pos| {
        if (ch == sep) {
            if (fi == idx) return line[s..pos];
            fi += 1;
            s = pos + 1;
        }
    }
    if (fi == idx) return line[s..];
    return "";
}
fn restOf(line: []const u8, sep: u8, idx: usize) []const u8 {
    var fi: usize = 0;
    for (line, 0..) |ch, pos| {
        if (ch == sep) {
            if (fi == idx) return line[pos + 1 ..];
            fi += 1;
        }
    }
    return "";
}
