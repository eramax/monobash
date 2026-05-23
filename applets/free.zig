const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "free", .main = main };

const MemInfo = struct {
    mem_total: u64,
    mem_free: u64,
    buffers: u64,
    cached: u64,
    swap_total: u64,
    swap_free: u64,
};

pub fn main(args: [][]const u8) u8 {
    var unit: u8 = 'k';
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h")) {
            unit = 'h';
        } else if (std.mem.eql(u8, arg, "-m")) {
            unit = 'm';
        } else if (std.mem.eql(u8, arg, "-g")) {
            unit = 'g';
        } else if (std.mem.eql(u8, arg, "-k")) {
            unit = 'k';
        } else {
            return core.die(1, "usage: free [-k|-m|-g|-h]\n", .{});
        }
    }

    const info = parseMeminfo() orelse return core.die(1, "free: cannot read /proc/meminfo\n", .{});

    const used = info.mem_total - info.mem_free;
    const avail = info.mem_free + info.buffers + info.cached;
    const swap_used = info.swap_total - info.swap_free;

    const divisor: u64 = switch (unit) {
        'h' => 1024,
        'm' => 1024 * 1024,
        'g' => 1024 * 1024 * 1024,
        else => 1,
    };
    const div = @max(divisor, 1);



    if (unit == 'h') {
        core.writeAll(1, "               total        used        free      shared  buff/cache   available\n");
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "Mem:    {d:>8.1}  {d:>8.1}  {d:>8.1}  {d:>8.1}  {d:>8.1}  {d:>8.1}\n", .{
            @as(f64, @floatFromInt(info.mem_total)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(used)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(info.mem_free)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(0)),
            @as(f64, @floatFromInt(info.buffers + info.cached)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(avail)) / 1024.0 / 1024.0,
        }) catch "";
        core.writeAll(1, line);
        const line2 = std.fmt.bufPrint(&buf, "Swap:   {d:>8.1}  {d:>8.1}  {d:>8.1}\n", .{
            @as(f64, @floatFromInt(info.swap_total)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(swap_used)) / 1024.0 / 1024.0,
            @as(f64, @floatFromInt(info.swap_free)) / 1024.0 / 1024.0,
        }) catch "";
        core.writeAll(1, line2);
    } else {
        core.writeAll(1, "               total        used        free      shared  buff/cache   available\n");
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "Mem:    {d:>8}  {d:>8}  {d:>8}  {d:>8}  {d:>8}  {d:>8}\n", .{
            info.mem_total / div,
            used / div,
            info.mem_free / div,
            @as(u64, 0),
            (info.buffers + info.cached) / div,
            avail / div,
        }) catch "";
        core.writeAll(1, line);
        const line2 = std.fmt.bufPrint(&buf, "Swap:   {d:>8}  {d:>8}  {d:>8}\n", .{
            info.swap_total / div,
            swap_used / div,
            info.swap_free / div,
        }) catch "";
        core.writeAll(1, line2);
    }

    return 0;
}

fn parseMeminfo() ?MemInfo {
    const fd = core.c.open("/proc/meminfo", core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);

    const data = core.readAll(std.heap.page_allocator, fd, 4096) catch return null;
    defer std.heap.page_allocator.free(data);

    var result = MemInfo{
        .mem_total = 0,
        .mem_free = 0,
        .buffers = 0,
        .cached = 0,
        .swap_total = 0,
        .swap_free = 0,
    };

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            result.mem_total = parseValue(line);
        } else if (std.mem.startsWith(u8, line, "MemFree:")) {
            result.mem_free = parseValue(line);
        } else if (std.mem.startsWith(u8, line, "Buffers:")) {
            result.buffers = parseValue(line);
        } else if (std.mem.startsWith(u8, line, "Cached:")) {
            result.cached = parseValue(line);
        } else if (std.mem.startsWith(u8, line, "SwapTotal:")) {
            result.swap_total = parseValue(line);
        } else if (std.mem.startsWith(u8, line, "SwapFree:")) {
            result.swap_free = parseValue(line);
        }
    }

    return result;
}

fn parseValue(line: []const u8) u64 {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return 0;
    const rest = std.mem.trim(u8, line[colon + 1 ..], " \t");
    const space = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const num_str = rest[0..space];
    return std.fmt.parseInt(u64, num_str, 10) catch 0;
}
