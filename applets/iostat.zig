const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "iostat", .main = main };

const alloc = std.heap.page_allocator;

fn readCpuStats(buf: []u8) ?struct { user: u64, nice: u64, system: u64, idle: u64, iowait: u64, irq: u64, softirq: u64, steal: u64 } {
    if (buf.len < 4 or !std.mem.startsWith(u8, buf, "cpu ")) return null;
    const rest = std.mem.trimStart(u8, buf[4..], " ");
    var it = std.mem.tokenizeScalar(u8, rest, ' ');
    const user = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const nice = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const system = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const idle = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const iowait = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const irq = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const softirq = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    const steal = std.fmt.parseUnsigned(u64, it.next() orelse return null, 10) catch return null;
    return .{ .user = user, .nice = nice, .system = system, .idle = idle, .iowait = iowait, .irq = irq, .softirq = softirq, .steal = steal };
}

fn pctStr(buf: []u8, val: u64, total: u64) []const u8 {
    if (total == 0) return " 0.0";
    const p = val * 1000 / total;
    const whole = p / 10;
    const frac = p % 10;
    _ = std.fmt.bufPrint(buf, "{d:>3}.{d}", .{ whole, frac }) catch return " 0.0";
    return buf[0..5];
}

pub fn main(args: [][]const u8) u8 {
    var opt_extended = false;
    var opt_device_only = false;
    var opt_kb = false;
    var opt_mb = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-x")) opt_extended = true;
        if (std.mem.eql(u8, arg, "-d")) opt_device_only = true;
        if (std.mem.eql(u8, arg, "-k")) opt_kb = true;
        if (std.mem.eql(u8, arg, "-m")) opt_mb = true;
    }

    if (!opt_device_only) {
        const stat_fd = core.openRead("/proc/stat");
        if (stat_fd == null) return core.die(1, "iostat: cannot open /proc/stat\n", .{});
        defer _ = core.c.close(stat_fd.?);
        const stat_data = core.readAll(alloc, stat_fd.?, 16384) catch return 1;
        defer alloc.free(stat_data);

        if (readCpuStats(stat_data)) |cpu| {
            const total = cpu.user + cpu.nice + cpu.system + cpu.idle + cpu.iowait + cpu.irq + cpu.softirq + cpu.steal;
            core.writeAll(1, "avg-cpu:  %user   %nice %system %iowait  %steal   %idle\n");
            var buf: [128]u8 = undefined;
            var pb: [6][6]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "          {s}   {s}   {s}   {s}   {s}   {s}\n", .{
                pctStr(&pb[0], cpu.user, total),
                pctStr(&pb[1], cpu.nice, total),
                pctStr(&pb[2], cpu.system, total),
                pctStr(&pb[3], cpu.iowait, total),
                pctStr(&pb[4], cpu.steal, total),
                pctStr(&pb[5], cpu.idle, total),
            }) catch return 1;
            core.writeAll(1, line);
        }
    }

    const disk_fd = core.openRead("/proc/diskstats");
    if (disk_fd == null) return core.die(1, "iostat: cannot open /proc/diskstats\n", .{});
    defer _ = core.c.close(disk_fd.?);
    const disk_data = core.readAll(alloc, disk_fd.?, 131072) catch return 1;
    defer alloc.free(disk_data);

    const divisor: u64 = if (opt_mb) 1024 * 1024 / 512 else if (opt_kb) 1024 / 512 else 1;
    const unit: []const u8 = if (opt_mb) "MB" else if (opt_kb) "KB" else "blk";

    core.writeAll(1, "\nDevice:            tps");
    if (opt_extended) {
        core.writeAll(1, "    rd_kB/s    wr_kB/s   rd_sec/s   wr_sec/s avgrq-sz avgqu-sz   await r_await w_await  svctm  %util");
    } else {
        var hdr_buf: [64]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "    {s}_read/s {s}_writ/s\n", .{ unit, unit }) catch "";
        core.writeAll(1, hdr);
    }
    core.writeAll(1, "\n");

    var pos: usize = 0;
    while (pos < disk_data.len) {
        const nl = std.mem.indexOfScalar(u8, disk_data[pos..], '\n') orelse disk_data.len;
        const line = disk_data[pos .. pos + nl];
        pos += nl + 1;
        if (line.len == 0) continue;

        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const major = it.next() orelse continue;
        const minor = it.next() orelse continue;
        _ = major;
        _ = minor;
        const name = it.next() orelse continue;
        const rio = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const rmerge = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const rsect = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const ruse = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const wio = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const wmerge = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const wsect = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        const wuse = std.fmt.parseUnsigned(u64, it.next() orelse continue, 10) catch continue;
        _ = rmerge;
        _ = ruse;
        _ = wmerge;
        _ = wuse;

        const ios = rio + wio;
        const rsect_val = rsect / divisor;
        const wsect_val = wsect / divisor;

        var out: [256]u8 = undefined;
        const out_line = std.fmt.bufPrint(&out, "{s:<16} {d:>6}  {d:>8}  {d:>8}\n", .{
            name, ios, rsect_val, wsect_val,
        }) catch continue;
        core.writeAll(1, out_line);
    }

    return 0;
}
