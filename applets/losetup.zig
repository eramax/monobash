const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "losetup", .main = main };

const LoopInfo = struct {
    name: []const u8,
    backing_file: []const u8,
    offset: u64,
    sizelimit: u64,
};

fn readLoopInfo(alloc: std.mem.Allocator, loop_name: []const u8) ?LoopInfo {
    var path_buf: [4096]u8 = undefined;
    const backing_path = std.fmt.bufPrint(&path_buf, "/sys/block/{s}/loop/backing_file", .{loop_name}) catch return null;
    var z_buf: [4096:0]u8 = undefined;
    if (backing_path.len >= z_buf.len) return null;
    @memcpy(z_buf[0..backing_path.len], backing_path);
    z_buf[backing_path.len] = 0;
    const data = readSysFile(alloc, z_buf[0..backing_path.len :0]) catch return null;
    defer alloc.free(data);
    const backing = std.mem.trim(u8, data, " \t\r\n");
    if (backing.len == 0) return null;

    var offset: u64 = 0;
    var sizelimit: u64 = 0;
    if (std.fmt.bufPrint(&path_buf, "/sys/block/{s}/loop/offset", .{loop_name})) |offset_path| {
        @memcpy(z_buf[0..offset_path.len], offset_path);
        z_buf[offset_path.len] = 0;
        if (readSysFile(alloc, z_buf[0..offset_path.len :0])) |off_data| {
            offset = std.fmt.parseInt(u64, std.mem.trim(u8, off_data, " \t\r\n"), 10) catch 0;
            alloc.free(off_data);
        } else |_| {}
    } else |_| {}
    if (std.fmt.bufPrint(&path_buf, "/sys/block/{s}/loop/sizelimit", .{loop_name})) |sl_path| {
        @memcpy(z_buf[0..sl_path.len], sl_path);
        z_buf[sl_path.len] = 0;
        if (readSysFile(alloc, z_buf[0..sl_path.len :0])) |sl_data| {
            sizelimit = std.fmt.parseInt(u64, std.mem.trim(u8, sl_data, " \t\r\n"), 10) catch 0;
            alloc.free(sl_data);
        } else |_| {}
    } else |_| {}

    const backing_dup = alloc.dupe(u8, backing) catch return null;
    const name_dup = alloc.dupe(u8, loop_name) catch return null;
    return LoopInfo{
        .name = name_dup,
        .backing_file = backing_dup,
        .offset = offset,
        .sizelimit = sizelimit,
    };
}

fn readSysFile(alloc: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    const fd = core.c.open(path.ptr, core.c.O_RDONLY);
    if (fd < 0) return error.OpenFailed;
    defer _ = core.c.close(fd);
    return core.readAll(alloc, fd, 4096);
}

fn listAll(alloc: std.mem.Allocator) void {
    const fd = core.c.open("/proc/partitions", core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    _ = lines.next();

    var header_done = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, std.mem.trim(u8, line, " \t"), ' ');
        var field_count: usize = 0;
        var name: []const u8 = "";
        while (fields.next()) |f| {
            if (f.len == 0) continue;
            field_count += 1;
            if (field_count == 4) name = f;
        }
        if (name.len == 0) continue;
        if (!std.mem.startsWith(u8, name, "loop")) continue;

        if (!header_done) {
            core.writeAll(1, "NAME       BACK-FILE\n");
            header_done = true;
        }

        if (readLoopInfo(alloc, name)) |info| {
            var buf: [4096]u8 = undefined;
            if (std.fmt.bufPrint(&buf, "{s:<10} {s}\n", .{ info.name, info.backing_file })) |out| {
                core.writeAll(1, out);
            } else |_| {}
            alloc.free(info.name);
            alloc.free(info.backing_file);
        }
    }
}

fn findUnused(alloc: std.mem.Allocator) u8 {
    const fd = core.c.open("/proc/partitions", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return 1;
    defer alloc.free(data);

    var loop_num: u8 = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, std.mem.trim(u8, line, " \t"), ' ');
        var field_count: usize = 0;
        var name: []const u8 = "";
        while (fields.next()) |f| {
            if (f.len == 0) continue;
            field_count += 1;
            if (field_count == 4) name = f;
        }
        if (name.len == 0) continue;
        if (std.mem.startsWith(u8, name, "loop")) {
            const num = std.fmt.parseInt(u8, name[4..], 10) catch continue;
            if (num >= loop_num) loop_num = num + 1;
        }
    }
    var buf: [64]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "/dev/loop{d}\n", .{loop_num}) catch return 1;
    core.writeAll(1, out);
    return 0;
}

fn findByFile(alloc: std.mem.Allocator, file: []const u8) u8 {
    const fd = core.c.open("/proc/partitions", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return 1;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, std.mem.trim(u8, line, " \t"), ' ');
        var field_count: usize = 0;
        var name: []const u8 = "";
        while (fields.next()) |f| {
            if (f.len == 0) continue;
            field_count += 1;
            if (field_count == 4) name = f;
        }
        if (name.len == 0) continue;
        if (!std.mem.startsWith(u8, name, "loop")) continue;

        if (readLoopInfo(alloc, name)) |info| {
            if (std.mem.eql(u8, info.backing_file, file)) {
                var buf: [4096]u8 = undefined;
                if (std.fmt.bufPrint(&buf, "/dev/{s}: {s}\n", .{ info.name, info.backing_file })) |out| {
                    core.writeAll(1, out);
                } else |_| {}
                alloc.free(info.name);
                alloc.free(info.backing_file);
                return 0;
            }
            alloc.free(info.name);
            alloc.free(info.backing_file);
        }
    }
    return core.die(1, "losetup: {s}: no loop device associated\n", .{file});
}

fn setupLoop(alloc: std.mem.Allocator, loopdev: []const u8, file: []const u8) u8 {
    // losetup LOOPDEV FILE - just report without actual ioctl
    _ = alloc;
    var z_buf: [4096:0]u8 = undefined;
    const path = if (std.mem.startsWith(u8, loopdev, "/dev/")) loopdev else blk: {
        const p = std.fmt.bufPrint(&z_buf, "/dev/{s}", .{loopdev}) catch return 1;
        @memcpy(z_buf[0..p.len], p);
        z_buf[p.len] = 0;
        break :blk z_buf[0..p.len :0];
    };
    _ = path;
    var buf: [4096]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "losetup: {s}: {s}: setup not supported (no ioctl)\n", .{ loopdev, file }) catch return 1;
    core.writeAll(1, out);
    return 1;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;

    if (args.len == 1) {
        listAll(alloc);
        return 0;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-f")) {
            return findUnused(alloc);
        } else if (std.mem.eql(u8, arg, "-j") and i + 1 < args.len) {
            i += 1;
            return findByFile(alloc, args[i]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "losetup: invalid option '{s}'\n", .{arg});
        } else {
            // First non-option is loopdev, second is file
            if (i + 1 < args.len) {
                const loopdev = arg;
                i += 1;
                const file = args[i];
                return setupLoop(alloc, loopdev, file);
            }
            return core.die(1, "losetup: usage: losetup [-f] [-j FILE] [LOOPDEV FILE]\n", .{});
        }
    }

    return 0;
}
