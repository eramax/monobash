const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "fmt", .main = main };
pub fn main(args: [][]const u8) u8 {
    var width: usize = 75;
    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "-w")) {
        i += 1;
        if (i >= args.len) return core.die(1, "fmt: missing number after -w\n", .{});
        width = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "fmt: invalid width\n", .{});
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
    defer alloc.free(data);
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
    var pi: usize = 0;
    while (pi < lc) {
        if (lines[pi].len == 0) {
            core.writeAll(1, "\n");
            pi += 1;
            continue;
        }
        start = pi;
        while (pi < lc and lines[pi].len > 0) pi += 1;
        fillParagraph(lines[start..pi], width);
    }
    return 0;
}
fn fillParagraph(lines: [][]const u8, width: usize) void {
    var words: [65536][]const u8 = undefined;
    var wc: usize = 0;
    for (lines) |line| {
        var ws: usize = 0;
        for (line, 0..) |ch, pos| {
            if (ch == ' ' or ch == '\t') {
                if (pos > ws) {
                    if (wc < words.len) words[wc] = line[ws..pos];
                    wc += 1;
                }
                ws = pos + 1;
            }
        }
        if (line.len > ws) {
            if (wc < words.len) words[wc] = line[ws..];
            wc += 1;
        }
    }
    var col: usize = 0;
    var wi: usize = 0;
    while (wi < wc) : (wi += 1) {
        const w = words[wi];
        if (col == 0) {
            core.writeAll(1, w);
            col = w.len;
        } else if (col + 1 + w.len <= width) {
            core.writeAll(1, " ");
            core.writeAll(1, w);
            col += 1 + w.len;
        } else {
            core.writeAll(1, "\n");
            core.writeAll(1, w);
            col = w.len;
        }
    }
    core.writeAll(1, "\n");
}
