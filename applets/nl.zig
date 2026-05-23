const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "nl", .main = main };
pub fn main(args: [][]const u8) u8 {
    var body: enum { all, nonempty, none } = .nonempty;
    var fmt: enum { ln, rn, rz } = .rn;
    var width: usize = 6;
    var sep: []const u8 = "\t";
    var start: usize = 1;
    var inc: usize = 1;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        if (std.mem.eql(u8, arg, "-b")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -b\n", .{});
            if (std.mem.eql(u8, args[i], "a")) { body = .all; }
            else if (std.mem.eql(u8, args[i], "t")) { body = .nonempty; }
            else if (std.mem.eql(u8, args[i], "n")) { body = .none; }
            else { return core.die(1, "nl: invalid body type '{s}'\n", .{args[i]}); }
            i += 1;
        } else if (std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -n\n", .{});
            if (std.mem.eql(u8, args[i], "ln")) { fmt = .ln; }
            else if (std.mem.eql(u8, args[i], "rn")) { fmt = .rn; }
            else if (std.mem.eql(u8, args[i], "rz")) { fmt = .rz; }
            else { return core.die(1, "nl: unknown format '{s}'\n", .{args[i]}); }
            i += 1;
        } else if (std.mem.eql(u8, arg, "-w")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -w\n", .{});
            width = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "nl: invalid width\n", .{});
            i += 1;
        } else if (std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -s\n", .{});
            sep = args[i];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -i\n", .{});
            inc = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "nl: invalid increment\n", .{});
            i += 1;
        } else if (std.mem.eql(u8, arg, "-v")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing argument after -v\n", .{});
            start = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "nl: invalid start\n", .{});
            i += 1;
        } else if (arg.len > 1 and arg[1] == 'b') {
            if (arg.len > 2) {
                switch (arg[2]) {
                    'a' => body = .all,
                    't' => body = .nonempty,
                    'n' => body = .none,
                    else => return core.die(1, "nl: invalid body type '{c}'\n", .{arg[2]}),
                }
            }
            i += 1;
        } else {
            return core.die(1, "nl: unknown option '{s}'\n", .{arg});
        }
    }
    const files = args[i..];
    var rc: u8 = 0;
    if (files.len == 0) {
        processFd(0, body, fmt, width, sep, start, inc);
    } else {
        for (files) |f| {
            var buf: [4096:0]u8 = undefined;
            if (f.len >= buf.len) { rc = 1; continue; }
            @memcpy(buf[0..f.len], f);
            buf[f.len] = 0;
            const fd = core.c.open(&buf, core.c.O_RDONLY);
            if (fd < 0) {
                core.eprint("nl: cannot open '{s}'\n", .{f});
                rc = 1;
                continue;
            }
            processFd(fd, body, fmt, width, sep, start, inc);
            _ = core.c.close(fd);
        }
    }
    return rc;
}
fn processFd(fd: c_int, body: anytype, fmt: anytype, width: usize, sep: []const u8, start: usize, inc: usize) void {
    _ = fmt;
    var reader = core.LineReader.init(fd);
    var lineno: usize = start;
    var num_buf: [64]u8 = undefined;
    const empty_str_len = width + sep.len;
    while (reader.next()) |line| {
        const number_it = switch (body) {
            .all => true,
            .nonempty => line.len > 0,
            .none => false,
        };
        if (number_it) {
            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{lineno}) catch "?";
            const pad_len = width -| num_str.len;
            var k: usize = 0;
            while (k < pad_len) { core.writeAll(1, " "); k += 1; }
            core.writeAll(1, num_str);
            core.writeAll(1, sep);
            lineno += inc;
        } else {
            var k: usize = 0;
            while (k < empty_str_len) { core.writeAll(1, " "); k += 1; }
        }
        core.writeAll(1, line);
        core.writeAll(1, "\n");
    }
}
