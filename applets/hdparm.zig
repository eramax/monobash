const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "hdparm", .main = main };

fn readSysFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var z_buf: [4096:0]u8 = undefined;
    if (path.len >= z_buf.len) return error.PathTooLong;
    @memcpy(z_buf[0..path.len], path);
    z_buf[path.len] = 0;
    const fd = core.c.open(z_buf[0..path.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return error.OpenFailed;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 4096);
}

fn printSysFile(alloc: std.mem.Allocator, label: []const u8, path: []const u8) void {
    const data = readSysFile(alloc, path) catch return;
    defer alloc.free(data);
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    var buf: [4096]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, " {s}: {s}\n", .{ label, trimmed }) catch return;
    core.writeAll(1, out);
}

fn identify(alloc: std.mem.Allocator, device: []const u8) void {
    var buf: [4096]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "\n{s}:\n", .{device}) catch return;
    core.writeAll(1, header);

    const dev_basename = std.fs.path.basename(device);
    const sys_base = std.fmt.bufPrint(&buf, "/sys/block/{s}", .{dev_basename}) catch return;

    const queue_path = std.fmt.bufPrint(&buf, "{s}/queue", .{sys_base}) catch return;
    _ = queue_path;

    // Queue parameters
    const qfiles = [_]struct { label: []const u8, sub: []const u8 }{
        .{ .label = "read_ahead_kb", .sub = "read_ahead_kb" },
        .{ .label = "max_sectors_kb", .sub = "max_sectors_kb" },
        .{ .label = "nr_requests", .sub = "nr_requests" },
        .{ .label = "scheduler", .sub = "scheduler" },
        .{ .label = "rotational", .sub = "rotational" },
        .{ .label = "hctx_queues", .sub = "hctx_queues" },
        .{ .label = "iostats", .sub = "iostats" },
        .{ .label = "io_poll", .sub = "io_poll" },
        .{ .label = "logical_block_size", .sub = "logical_block_size" },
        .{ .label = "physical_block_size", .sub = "physical_block_size" },
        .{ .label = "minimum_io_size", .sub = "minimum_io_size" },
        .{ .label = "optimal_io_size", .sub = "optimal_io_size" },
        .{ .label = "write_same_max_bytes", .sub = "write_same_max_bytes" },
        .{ .label = "discard_granularity", .sub = "discard_granularity" },
        .{ .label = "discard_max_bytes", .sub = "discard_max_bytes" },
        .{ .label = "dax", .sub = "dax" },
        .{ .label = "wc", .sub = "wc" },
        .{ .label = "fua", .sub = "fua" },
    };

    for (qfiles) |qf| {
        const path = std.fmt.bufPrint(&buf, "{s}/queue/{s}", .{ sys_base, qf.sub }) catch continue;
        printSysFile(alloc, qf.label, path);
    }

    // Device parameters
    const dfiles = [_]struct { label: []const u8, sub: []const u8 }{
        .{ .label = "vendor", .sub = "device/vendor" },
        .{ .label = "model", .sub = "device/model" },
        .{ .label = "rev", .sub = "device/rev" },
        .{ .label = "state", .sub = "device/state" },
        .{ .label = "timeout", .sub = "device/timeout" },
        .{ .label = "queue_depth", .sub = "device/queue_depth" },
        .{ .label = "device_block_size", .sub = "device/block_size" },
        .{ .label = "wwwn", .sub = "device/wwid" },
    };

    for (dfiles) |df| {
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ sys_base, df.sub }) catch continue;
        printSysFile(alloc, df.label, path);
    }
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var device: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-I") or std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "-T")) {
            // flags accepted but not selectively implemented
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "hdparm: invalid option '{s}'\n", .{arg});
        } else {
            device = arg;
        }
    }

    const dev = device orelse return core.die(1, "hdparm: usage: hdparm [-I] [-t] [-T] DEVICE\n", .{});

    identify(alloc, dev);

    return 0;
}
