const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "dc", .main = main };
pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;
    var stack = std.ArrayListAligned(i64, null).empty;
    defer stack.deinit(alloc);
    var reader = core.LineReader.init(0);
    var rbuf: [128]u8 = undefined;
    while (reader.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        while (it.next()) |tok| {
            if (tok.len == 1) {
                switch (tok[0]) {
                    'p' => {
                        if (stack.items.len == 0) { core.writeAll(2, "dc: stack empty\n"); continue; }
                        const s = std.fmt.bufPrint(&rbuf, "{d}\n", .{stack.items[stack.items.len - 1]}) catch "";
                        core.writeAll(1, s);
                    },
                    'n' => {
                        if (stack.items.len == 0) { core.writeAll(2, "dc: stack empty\n"); continue; }
                        const s = std.fmt.bufPrint(&rbuf, "{d}\n", .{stack.pop().?}) catch "";
                        core.writeAll(1, s);
                    },
                    'f' => {
                        var j: usize = stack.items.len;
                        while (j > 0) { j -= 1;
                            const s = std.fmt.bufPrint(&rbuf, "{d}\n", .{stack.items[j]}) catch "";
                            core.writeAll(1, s);
                        }
                    },
                    '+', '-', '*', '/', '%' => {
                        if (stack.items.len < 2) { core.writeAll(2, "dc: stack underflow\n"); continue; }
                        const b = stack.pop().?;
                        const a = stack.pop().?;
                        const r = switch (tok[0]) {
                            '+' => a + b,
                            '-' => a - b,
                            '*' => a * b,
                            '/' => if (b == 0) { core.writeAll(2, "dc: divide by zero\n"); stack.append(alloc, a) catch {}; stack.append(alloc, b) catch {}; continue; } else @divTrunc(a, b),
                            '%' => if (b == 0) { core.writeAll(2, "dc: modulo by zero\n"); stack.append(alloc, a) catch {}; stack.append(alloc, b) catch {}; continue; } else @mod(a, b),
                            else => unreachable,
                        };
                        stack.append(alloc, r) catch return 1;
                    },
                    else => {
                        const n = std.fmt.parseInt(i64, tok, 10) catch { core.writeAll(2, "dc: unknown command\n"); continue; };
                        stack.append(alloc, n) catch return 1;
                    },
                }
            } else {
                const n = std.fmt.parseInt(i64, tok, 10) catch { core.writeAll(2, "dc: unknown command\n"); continue; };
                stack.append(alloc, n) catch return 1;
            }
        }
    }
    return 0;
}
