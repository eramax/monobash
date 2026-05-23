const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "nl", .main = main };
pub fn main(args: [][]const u8) u8 {
    var body: enum { all, nonempty } = .nonempty;
    var fmt: enum { ln, rn, rz } = .rn;
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-ba")) {
            body = .all;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-bt")) {
            body = .nonempty;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) return core.die(1, "nl: missing format after -n\n", .{});
            if (std.mem.eql(u8, args[i], "ln")) {
                fmt = .ln;
            } else if (std.mem.eql(u8, args[i], "rn")) {
                fmt = .rn;
            } else if (std.mem.eql(u8, args[i], "rz")) {
                fmt = .rz;
            } else {
                return core.die(1, "nl: unknown format '{s}'\n", .{args[i]});
            }
            i += 1;
        } else {
            for (arg[1..]) |c| {
                switch (c) {
                    'b' => body = .all,
                    't' => body = .nonempty,
                    'n' => {},
                    else => return core.die(1, "nl: unknown flag '{c}'\n", .{c}),
                }
            }
            i += 1;
        }
    }
    var reader = core.LineReader.init(0);
    var lineno: usize = 0;
    while (reader.next()) |line| {
        const number_it = switch (body) {
            .all => true,
            .nonempty => line.len > 0,
        };
        if (number_it) {
            lineno += 1;
            var nbuf: [64]u8 = undefined;
            const ns = switch (fmt) {
                .ln => std.fmt.bufPrint(&nbuf, "{d:<6}", .{lineno}) catch "",
                .rn => std.fmt.bufPrint(&nbuf, "{d:>6}", .{lineno}) catch "",
                .rz => std.fmt.bufPrint(&nbuf, "{d:0>6}", .{lineno}) catch "",
            };
            core.writeAll(1, ns);
        } else {
            core.writeAll(1, "      ");
        }
        core.writeAll(1, "\t");
        core.writeAll(1, line);
        core.writeAll(1, "\n");
    }
    return 0;
}
