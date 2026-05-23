const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "pr", .main = main };
pub fn main(args: [][]const u8) u8 {
    var page_len: usize = 66;
    var header: []const u8 = "";
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-l")) {
            i += 1;
            if (i >= args.len) return core.die(1, "pr: missing number after -l\n", .{});
            page_len = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "pr: invalid page length\n", .{});
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-h")) {
            i += 1;
            if (i >= args.len) return core.die(1, "pr: missing header after -h\n", .{});
            header = args[i];
            i += 1;
        } else return core.die(1, "pr: unknown option: {s}\n", .{args[i]});
    }
    const files = args[i..];
    const alloc = std.heap.page_allocator;
    const body_lines = if (page_len > 3) page_len - 3 else 1;
    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
        defer alloc.free(data);
        printPages(1, data, header, body_lines, alloc);
    } else {
        for (files) |f| {
            const fd = core.openReadName(f) orelse {
                core.eprint("pr: cannot open '{s}'\n", .{f});
                continue;
            };
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 1024 * 1024) catch continue;
            defer alloc.free(data);
            const h = if (header.len > 0) header else f;
            printPages(1, data, h, body_lines, alloc);
        }
    }
    return 0;
}
fn printPages(fd: c_int, data: []const u8, header: []const u8, body_per_page: usize, alloc: std.mem.Allocator) void {
    _ = fd;
    _ = alloc;
    var lines: [65536][]const u8 = undefined;
    var lc: usize = 0;
    var start: usize = 0;
    for (data, 0..) |ch, pos| {
        if (ch == '\n') {
            if (lc < lines.len) lines[lc] = data[start..pos];
            lc += 1;
            start = pos + 1;
        }
    }
    if (start < data.len) { if (lc < lines.len) lines[lc] = data[start..]; lc += 1; }
    var page_no: usize = 1;
    var li: usize = 0;
    while (li < lc) {
        printHeader(header, page_no);
        var bi: usize = 0;
        while (bi < body_per_page and li < lc) : (bi += 1) {
            core.writeAll(1, lines[li]);
            core.writeAll(1, "\n");
            li += 1;
        }
        page_no += 1;
    }
}
fn printHeader(header: []const u8, page_no: usize) void {
    var now_buf: [64]u8 = undefined;
    const now_str = getDate(&now_buf);
    var hbuf: [4096]u8 = undefined;
    const hline = std.fmt.bufPrint(&hbuf, "{s}  {s}  Page {d}\n\n", .{ now_str, header, page_no }) catch return;
    core.writeAll(1, hline);
}
fn getDate(buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ 2026, 5, 23 }) catch "unknown";
}
