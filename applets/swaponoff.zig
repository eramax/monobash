const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "swapon", .main = main };
pub const meta_off = core.AppletMeta{ .name = "swapoff", .main = mainOff };

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    return doSwapon(alloc, args);
}

extern "c" fn swapon(path: [*c]u8, flags: c_int) c_int;
extern "c" fn swapoff(path: [*c]u8) c_int;

const SWAP_FLAG_PREFER: c_int = 0x8000;
const SWAP_FLAG_PRIO_MASK: c_int = 0x7fff;
const SWAP_FLAG_DISCARD: c_int = 0x10000;

fn parseFstabDevices(alloc: std.mem.Allocator, out: *std.ArrayListAligned([]const u8, null)) !void {
    const fd = core.c.open("/etc/fstab", core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, trimmed, ' ');
        const dev = fields.next() orelse continue;
        _ = fields.next(); // mountpoint
        const fstype = fields.next() orelse continue;
        if (std.mem.eql(u8, fstype, "swap")) {
            try out.append(try alloc.dupe(u8, dev));
        }
    }
}

fn doSwapon(alloc: std.mem.Allocator, argv: [][]const u8) u8 {
    var all_flag = false;
    var priority: ?c_int = null;
    var devices: std.ArrayListAligned([]const u8, null) = .empty;
    defer devices.deinit(alloc);

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "-a")) {
            all_flag = true;
        } else if (std.mem.eql(u8, arg, "-p") and i + 1 < argv.len) {
            i += 1;
            priority = std.fmt.parseInt(c_int, argv[i], 10) catch {
                return core.die(1, "swapon: invalid priority: {s}\n", .{argv[i]});
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "swapon: invalid option '{s}'\n", .{arg});
        } else {
            const dup = alloc.dupe(u8, arg) catch return 1;
            devices.append(alloc, dup) catch return 1;
        }
    }

    if (all_flag) {
        parseFstabDevices(alloc, &devices) catch {};
    }

    if (devices.items.len == 0) {
        return core.die(1, "swapon: usage: swapon [-a] [-p PRIORITY] DEVICE\n", .{});
    }

    var rc: u8 = 0;
    for (devices.items) |dev| {
        var z_buf: [4096:0]u8 = undefined;
        const dev_path = if (std.mem.startsWith(u8, dev, "/dev/")) dev else blk: {
            const p = std.fmt.bufPrint(&z_buf, "/dev/{s}", .{dev}) catch return 1;
            @memcpy(z_buf[0..p.len], p);
            z_buf[p.len] = 0;
            break :blk z_buf[0..p.len :0];
        };

        var flags: c_int = 0;
        if (priority) |prio| {
            flags |= SWAP_FLAG_PREFER | (prio & SWAP_FLAG_PRIO_MASK);
        }

        if (swapon(@as([*c]u8, @ptrCast(dev_path.ptr)), flags) != 0) {
            core.eprint("swapon: {s}: failed\n", .{dev_path});
            rc = 1;
        }
    }

    return rc;
}

fn mainOff(argv: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var all_flag = false;
    var devices: std.ArrayListAligned([]const u8, null) = .empty;
    defer devices.deinit(alloc);

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "-a")) {
            all_flag = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "swapoff: invalid option '{s}'\n", .{arg});
        } else {
            const dup = alloc.dupe(u8, arg) catch return 1;
            devices.append(alloc, dup) catch return 1;
        }
    }

    if (all_flag) {
        parseFstabDevices(alloc, &devices) catch {};
    }

    if (devices.items.len == 0) {
        return core.die(1, "swapoff: usage: swapoff [-a] DEVICE\n", .{});
    }

    var rc: u8 = 0;
    for (devices.items) |dev| {
        var z_buf: [4096:0]u8 = undefined;
        const dev_path = if (std.mem.startsWith(u8, dev, "/dev/")) dev else blk: {
            const p = std.fmt.bufPrint(&z_buf, "/dev/{s}", .{dev}) catch return 1;
            @memcpy(z_buf[0..p.len], p);
            z_buf[p.len] = 0;
            break :blk z_buf[0..p.len :0];
        };

        if (swapoff(@as([*c]u8, @ptrCast(dev_path.ptr))) != 0) {
            core.eprint("swapoff: {s}: failed\n", .{dev_path});
            rc = 1;
        }
    }

    return rc;
}
