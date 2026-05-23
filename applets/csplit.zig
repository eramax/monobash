const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "csplit", .main = main };

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var prefix: []const u8 = "xx";
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        if (std.mem.eql(u8, args[i][0..2], "-f")) {
            if (args[i].len > 2) {
                prefix = args[i][2..];
            } else {
                i += 1;
                if (i < args.len) prefix = args[i];
            }
        } else if (std.mem.eql(u8, args[i][0..2], "-n")) {
        } else return core.die(1, "csplit: invalid option: {s}\n", .{args[i]});
        i += 1;
    }
    if (i >= args.len) return core.die(1, "usage: csplit FILE /PATTERN/ [REP]\n", .{});
    const file = args[i];
    i += 1;
    var pattern: ?[]const u8 = null;
    var repeat: usize = 1;
    if (i < args.len) {
        const pat = args[i];
        if (pat.len > 2 and pat[0] == '/' and pat[pat.len - 1] == '/') {
            pattern = pat[1 .. pat.len - 1];
            i += 1;
            if (i < args.len) {
                repeat = std.fmt.parseInt(usize, args[i], 10) catch 1;
            }
        } else {
            return core.die(1, "csplit: expected /PATTERN/\n", .{});
        }
    }
    if (pattern == null) return core.die(1, "csplit: no pattern specified\n", .{});

    var fbuf: [4096:0]u8 = undefined;
    if (file.len >= fbuf.len) return 1;
    @memcpy(fbuf[0..file.len], file);
    fbuf[file.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "csplit: {s}: No such file\n", .{file});
    defer _ = core.c.close(fd);

    const alloc = std.heap.page_allocator;
    const content = core.readAll(alloc, fd, 1024 * 1024 * 16) catch return 1;
    defer alloc.free(content);

    var lines: std.ArrayListAligned([]const u8, null) = .empty;
    defer lines.deinit(alloc);
    var start: usize = 0;
    while (start < content.len) {
        const end = std.mem.indexOfScalar(u8, content[start..], '\n') orelse content.len - start;
        const line = if (start + end < content.len and content[start + end] == '\n')
            content[start .. start + end]
        else
            content[start..];
        lines.append(alloc, line) catch return 1;
        start += end + 1;
        if (start > content.len) break;
    }

    const pat = pattern.?;
    var out_idx: usize = 0;
    var line_idx: usize = 0;
    var rep_count: usize = 0;
    var buf: std.ArrayListAligned(u8, null) = .empty;
    defer buf.deinit(alloc);

    while (line_idx < lines.items.len) {
        const line = lines.items[line_idx];
        if (rep_count < repeat and std.mem.indexOf(u8, line, pat) != null) {
            if (buf.items.len > 0 or out_idx > 0) {
                const name = std.fmt.allocPrint(alloc, "{s}{d:0>2}", .{prefix, out_idx}) catch return 1;
                defer alloc.free(name);
                var nbuf: [4096:0]u8 = undefined;
                if (name.len >= nbuf.len) return 1;
                @memcpy(nbuf[0..name.len], name);
                nbuf[name.len] = 0;
                const ofd = core.c.open(&nbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
                if (ofd < 0) {
                    core.eprint("csplit: cannot create '{s}'\n", .{name});
                    return 1;
                }
                core.writeAll(ofd, buf.items);
                const size_str = std.fmt.allocPrint(alloc, "{d}\n", .{buf.items.len}) catch return 1;
                core.writeAll(1, size_str);
                alloc.free(size_str);
                _ = core.c.close(ofd);
                buf.clearRetainingCapacity();
                out_idx += 1;
            }
            rep_count += 1;
        }
        buf.appendSlice(alloc, line) catch return 1;
        buf.append(alloc, '\n') catch return 1;
        line_idx += 1;
    }
    if (buf.items.len > 0) {
        const name = std.fmt.allocPrint(alloc, "{s}{d:0>2}", .{prefix, out_idx}) catch return 1;
        defer alloc.free(name);
        var nbuf: [4096:0]u8 = undefined;
        if (name.len >= nbuf.len) return 1;
        @memcpy(nbuf[0..name.len], name);
        nbuf[name.len] = 0;
        const ofd = core.c.open(&nbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
        if (ofd < 0) {
            core.eprint("csplit: cannot create '{s}'\n", .{name});
            return 1;
        }
        core.writeAll(ofd, buf.items);
        const size_str = std.fmt.allocPrint(alloc, "{d}\n", .{buf.items.len}) catch return 1;
        core.writeAll(1, size_str);
        alloc.free(size_str);
        _ = core.c.close(ofd);
    }
    return 0;
}
