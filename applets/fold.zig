const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "fold", .main = main };

pub fn main(args: [][]const u8) u8 {
    var width: usize = 80;
    var break_spaces = false;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        var j: usize = 1;
        var done = false;
        while (j < arg.len and !done) {
            switch (arg[j]) {
                's' => { break_spaces = true; j += 1; },
                'w' => {
                    if (j + 1 < arg.len) {
                        width = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch return core.die(1, "fold: invalid width\n", .{});
                        done = true;
                    } else {
                        i += 1;
                        if (i >= args.len) return core.die(1, "fold: missing number after -w\n", .{});
                        width = std.fmt.parseUnsigned(usize, args[i], 10) catch return core.die(1, "fold: invalid width\n", .{});
                    }
                    j = arg.len; // skip rest
                },
                '0'...'9' => {
                    width = std.fmt.parseUnsigned(usize, arg[j..], 10) catch return core.die(1, "fold: invalid width\n", .{});
                    done = true;
                    j = arg.len;
                },
                else => return core.die(1, "fold: unknown flag '{c}'\n", .{arg[j]}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    var rc: u8 = 0;
    if (files.len == 0) {
        processFd(0, width, break_spaces);
    } else {
        for (files) |f| {
            var buf: [4096:0]u8 = undefined;
            if (f.len >= buf.len) { rc = 1; continue; }
            @memcpy(buf[0..f.len], f);
            buf[f.len] = 0;
            const fd = core.c.open(&buf, core.c.O_RDONLY);
            if (fd < 0) {
                core.eprint("fold: cannot open '{s}'\n", .{f});
                rc = 1;
                continue;
            }
            processFd(fd, width, break_spaces);
            _ = core.c.close(fd);
        }
    }
    return rc;
}

fn adjustColumn(col: usize, c: u8) usize {
    return if (c == '\t') col + 8 - col % 8 else col + 1;
}

fn processFd(fd: c_int, width: usize, break_spaces: bool) void {
    var line_out: [65536]u8 = undefined;
    var offset: usize = 0;
    var column: usize = 0;
    var buf: [4096]u8 = undefined;
    var buf_pos: usize = 0;
    var buf_end: usize = 0;

    while (true) {
        if (buf_pos >= buf_end) {
            const n = core.c.read(fd, &buf, buf.len);
            if (n <= 0) break;
            buf_end = @intCast(n);
            buf_pos = 0;
        }
        const c = buf[buf_pos];
        buf_pos += 1;

        while (true) {
            if (c == '\n') {
                if (offset >= line_out.len) return;
                line_out[offset] = '\n';
                core.writeAll(1, line_out[0..offset + 1]);
                column = 0;
                offset = 0;
                break;
            }
            const new_col = adjustColumn(column, c);
            if (new_col <= width or offset == 0) {
                if (offset >= line_out.len) return;
                line_out[offset] = c;
                column = new_col;
                offset += 1;
                break;
            }
            if (break_spaces) {
                var found: ?usize = null;
                var j: usize = offset;
                while (j > 0) {
                    j -= 1;
                    if (line_out[j] == ' ' or line_out[j] == '\t') { found = j; break; }
                }
                if (found) |fb| {
                    core.writeAll(1, line_out[0..fb + 1]);
                    core.writeAll(1, "\n");
                    const remaining = offset - fb - 1;
                    if (remaining > 0) {
                        std.mem.copyForwards(u8, line_out[0..], line_out[fb + 1 .. offset]);
                    }
                    offset = remaining;
                    column = 0;
                    var k: usize = 0;
                    while (k < offset) {
                        column = adjustColumn(column, line_out[k]);
                        k += 1;
                    }
                    continue;
                }
            }
            if (offset >= line_out.len) return;
            line_out[offset] = '\n';
            core.writeAll(1, line_out[0..offset + 1]);
            column = 0;
            offset = 0;
        }
    }

    if (offset > 0) {
        core.writeAll(1, line_out[0..offset]);
    }
}
