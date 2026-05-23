const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sum", .main = main };

fn bsdSum(data: []const u8) u32 {
    var sum: u32 = 0;
    for (data) |b| {
        sum = (sum >> 1) + ((sum & 1) << 15);
        sum +%= b;
        sum &= 0xffff;
    }
    return sum;
}

fn sysvSum(data: []const u8) u32 {
    var s: u32 = 0;
    for (data) |b| s +%= b;
    const r = (s & 0xffff) + (s >> 16);
    s = (r & 0xffff) + (r >> 16);
    return s & 0xffff;
}

fn sumFile(fd: c_int, use_sysv: bool) !struct { sum: u32, blocks: u64 } {
    const alloc = std.heap.page_allocator;
    const data = try core.readAll(alloc, fd, 1024 * 1024 * 16);
    defer alloc.free(data);
    const sum = if (use_sysv) sysvSum(data) else bsdSum(data);
    const block_size: u64 = if (use_sysv) 512 else 1024;
    const blocks = (@as(u64, data.len) + block_size - 1) / block_size;
    return .{ .sum = sum, .blocks = blocks };
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var use_sysv = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            if (c == 's') use_sysv = true;
            if (c == 'r') use_sysv = false;
        }
        i += 1;
    }
    const files = args[i..];

    if (files.len == 0) {
        const result = sumFile(0, use_sysv) catch return 1;
        var buf: [128]u8 = undefined;
        if (use_sysv) {
            const s = std.fmt.bufPrint(&buf, "{d} {d}\n", .{ result.sum, result.blocks }) catch "";
            core.writeAll(1, s);
        } else {
            const s = std.fmt.bufPrint(&buf, "{d:0>5} {d:>5}\n", .{ result.sum, result.blocks }) catch "";
            core.writeAll(1, s);
        }
        return 0;
    }

    const print_name = files.len > 1 or use_sysv;
    var exit: u8 = 0;
    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) { exit = 1; continue; }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) { core.eprint("sum: {s}: No such file\n", .{f}); exit = 1; continue; }
        defer _ = core.c.close(fd);
        const result = sumFile(fd, use_sysv) catch { exit = 1; continue; };
        var buf: [512]u8 = undefined;
        if (use_sysv) {
            if (print_name) {
                const s = std.fmt.bufPrint(&buf, "{d} {d} {s}\n", .{ result.sum, result.blocks, f }) catch "";
                core.writeAll(1, s);
            } else {
                const s = std.fmt.bufPrint(&buf, "{d} {d}\n", .{ result.sum, result.blocks }) catch "";
                core.writeAll(1, s);
            }
        } else {
            if (print_name) {
                const s = std.fmt.bufPrint(&buf, "{d:0>5} {d:>5} {s}\n", .{ result.sum, result.blocks, f }) catch "";
                core.writeAll(1, s);
            } else {
                const s = std.fmt.bufPrint(&buf, "{d:0>5} {d:>5}\n", .{ result.sum, result.blocks }) catch "";
                core.writeAll(1, s);
            }
        }
    }
    return exit;
}
