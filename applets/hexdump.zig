const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "hexdump", .main = main };
pub fn main(args: [][]const u8) u8 {
    var canonical = false;
    var max_len: usize = 1024 * 1024 * 1024;
    var file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-C")) {
                canonical = true;
            } else if (std.mem.eql(u8, arg, "-n")) {
                i += 1;
                if (i >= args.len) return core.die(1, "hexdump: missing length after -n\n", .{});
                max_len = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "hexdump: invalid length\n", .{});
            } else if (std.mem.eql(u8, arg, "--")) {
                i += 1;
                break;
            } else return core.die(1, "hexdump: unknown flag '{s}'\n", .{arg});
        } else file = arg;
        i += 1;
    }
    const alloc = std.heap.page_allocator;
    var fd: c_int = 0;
    if (file) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) return core.die(1, "hexdump: path too long\n", .{});
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "hexdump: cannot open '{s}'\n", .{f});
    }
    defer {
        if (file != null and fd > 0) _ = core.c.close(fd);
    }
    const data = core.readAll(alloc, fd, max_len) catch return core.die(1, "hexdump: read error\n", .{});
    defer alloc.free(data);
    var offset: usize = 0;
    var lbuf: [256]u8 = undefined;
    while (offset < data.len) {
        const chunk = data[offset..@min(offset + 16, data.len)];
        if (canonical) {
            const off = std.fmt.bufPrint(&lbuf, "{x:0>8}  ", .{offset}) catch "";
            core.writeAll(1, off);
            var j: usize = 0;
            while (j < 16) {
                if (j < chunk.len) {
                    const h = std.fmt.bufPrint(&lbuf, "{x:0>2}", .{chunk[j]}) catch "";
                    core.writeAll(1, h);
                    core.writeAll(1, " ");
                } else {
                    core.writeAll(1, "   ");
                }
                if (j == 7) core.writeAll(1, " ");
                j += 1;
            }
            core.writeAll(1, " |");
            for (chunk) |b| {
                const c: u8 = if (b >= 32 and b < 127) b else '.';
                lbuf[0] = c;
                core.writeAll(1, lbuf[0..1]);
            }
            core.writeAll(1, "|\n");
        } else {
            const off = std.fmt.bufPrint(&lbuf, "{x:0>8} ", .{offset}) catch "";
            core.writeAll(1, off);
            for (chunk) |b| {
                const h = std.fmt.bufPrint(&lbuf, "{x:0>2} ", .{b}) catch "";
                core.writeAll(1, h);
            }
            var j: usize = chunk.len;
            while (j < 16) { core.writeAll(1, "   "); j += 1; }
            core.writeAll(1, " ");
            for (chunk) |b| {
                const c: u8 = if (b >= 32 and b < 127) b else '.';
                lbuf[0] = c;
                core.writeAll(1, lbuf[0..1]);
            }
            core.writeAll(1, "\n");
        }
        offset += 16;
    }
    // Final address line (only for canonical)
    if (canonical and data.len > 0) {
        const final_addr = std.fmt.bufPrint(&lbuf, "{x:0>8}\n", .{data.len}) catch "";
        core.writeAll(1, final_addr);
    }
    return 0;
}
