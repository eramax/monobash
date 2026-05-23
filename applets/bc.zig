const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "bc", .main = main };

const Allocator = std.mem.Allocator;

pub fn main(args: [][]const u8) u8 {
    _ = args;
    // Stub - basic arithmetic via existing expand.zig
    const alloc = std.heap.page_allocator;
    var reader = core.LineReader.init(0);
    while (reader.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const result = @import("../expand.zig").evalArithmeticFromStr(alloc, trimmed) catch {
            core.eprint("(standard_in) 1: syntax error\n", .{});
            continue;
        };
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}\n", .{result}) catch continue;
        core.writeAll(1, s);
    }
    return 0;
}
