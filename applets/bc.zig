const std = @import("std");
const core = @import("core.zig");
const expand = @import("../expand.zig");

pub const meta = core.AppletMeta{ .name = "bc", .main = main };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    if (args.len >= 2) {
        const expr = std.mem.join(alloc, " ", args[1..]) catch return 1;
        defer alloc.free(expr);
        const result = expand.evalArithmeticFromStr(alloc, expr) catch return 1;
        var buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{d}\n", .{result}) catch return 1;
        core.writeAll(1, line);
        return 0;
    }

    var reader = core.LineReader.init(0);
    while (reader.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const result = expand.evalArithmeticFromStr(alloc, trimmed) catch {
            core.eprint("bc: parse error: '{s}'\n", .{trimmed});
            continue;
        };
        var buf: [64]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{d}\n", .{result}) catch continue;
        core.writeAll(1, out);
    }

    return 0;
}
