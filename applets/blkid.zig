const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "blkid", .main = main };

const FsInfo = struct {
    uuid: []const u8 = "",
    label: []const u8 = "",
    fstype: []const u8 = "",
};

fn getFsInfo(fd: c_int) FsInfo {
    var buf: [2048]u8 = undefined;
    const n = core.c.read(fd, &buf, buf.len);
    if (n < 1024) return .{};

    // Check ext2/3/4 superblock (at offset 1024, magic at offset 56)
    const ext_magic = std.mem.readInt(u16, buf[1024 + 56 ..][0..2], .little);
    if (ext_magic == 0xEF53) {
        const uuid_bytes = buf[1024 + 104 ..][0..16];
        const label_bytes = buf[1024 + 120 ..][0..16];
        var uuid_hex: [36]u8 = undefined;
        _ = std.fmt.bufPrint(&uuid_hex, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            uuid_bytes[0], uuid_bytes[1], uuid_bytes[2], uuid_bytes[3],
            uuid_bytes[4], uuid_bytes[5], uuid_bytes[6], uuid_bytes[7],
            uuid_bytes[8], uuid_bytes[9], uuid_bytes[10], uuid_bytes[11],
            uuid_bytes[12], uuid_bytes[13], uuid_bytes[14], uuid_bytes[15],
        }) catch return .{};
        var label_str: [16]u8 = undefined;
        var label_len: usize = 0;
        while (label_len < 16 and label_bytes[label_len] != 0) {
            label_str[label_len] = label_bytes[label_len];
            label_len += 1;
        }

        // Check compat features to distinguish ext4 from ext3/ext2
        const incompat = std.mem.readInt(u32, buf[1024 + 316 ..][0..4], .little);

        const fstype = if (incompat & 0x40 != 0) "ext4" else if (incompat & 0x04 != 0) "ext3" else "ext2";

        return .{
            .uuid = uuid_hex[0..],
            .label = label_str[0..label_len],
            .fstype = fstype,
        };
    }

    // Check XFS superblock (at offset 0, magic "XFSB")
    if (n >= 4 and buf[0] == 'X' and buf[1] == 'F' and buf[2] == 'S' and buf[3] == 'B') {
        const uuid_bytes = buf[32..][0..16];
        var uuid_hex: [36]u8 = undefined;
        _ = std.fmt.bufPrint(&uuid_hex, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            uuid_bytes[0], uuid_bytes[1], uuid_bytes[2], uuid_bytes[3],
            uuid_bytes[4], uuid_bytes[5], uuid_bytes[6], uuid_bytes[7],
            uuid_bytes[8], uuid_bytes[9], uuid_bytes[10], uuid_bytes[11],
            uuid_bytes[12], uuid_bytes[13], uuid_bytes[14], uuid_bytes[15],
        }) catch return .{};
        var label_str: [12]u8 = undefined;
        var label_len: usize = 0;
        while (label_len < 12 and buf[108 + label_len] != 0) {
            label_str[label_len] = buf[108 + label_len];
            label_len += 1;
        }
        return .{
            .uuid = uuid_hex[0..],
            .label = label_str[0..label_len],
            .fstype = "xfs",
        };
    }

    // Check FAT/VFAT signature at offset 0 (0xEB?? or 0xE9) with "FAT" string at offset 54
    if (n >= 64) {
        const fat_types = [_]struct { off: usize, label: []const u8 }{
            .{ .off = 54, .label = "FAT" },
            .{ .off = 82, .label = "FAT32" },
        };
        for (fat_types) |ft| {
            if (buf[ft.off] == 'F' and buf[ft.off + 1] == 'A' and buf[ft.off + 2] == 'T') {
                const label_bytes = buf[ft.off + 3 ..][0..8];
                var label_str: [8]u8 = undefined;
                var label_len: usize = 0;
                while (label_len < 8 and label_bytes[label_len] != 0) {
                    label_str[label_len] = label_bytes[label_len];
                    label_len += 1;
                }
                return .{
                    .fstype = "vfat",
                    .label = label_str[0..label_len],
                };
            }
        }
    }

    return .{};
}

fn showDevice(name: []const u8, info: FsInfo, show_tag: ?[]const u8, format: []const u8) void {
    if (std.mem.eql(u8, format, "export")) {
        if (show_tag) |tag| {
            const val = if (std.mem.eql(u8, tag, "UUID")) info.uuid else if (std.mem.eql(u8, tag, "TYPE")) info.fstype else if (std.mem.eql(u8, tag, "LABEL")) info.label else "";
            if (val.len > 0) core.writeAll(1, "DEVNAME=") else return;
            core.writeAll(1, name);
            core.writeAll(1, " ");
            core.writeAll(1, tag);
            core.writeAll(1, "=");
            core.writeAll(1, val);
            core.writeAll(1, "\n");
        } else {
            var buf: [1024]u8 = undefined;
            const out = std.fmt.bufPrint(&buf, "DEVNAME={s} UUID={s} TYPE={s} LABEL={s}\n", .{ name, info.uuid, info.fstype, info.label }) catch return;
            core.writeAll(1, out);
        }
    } else if (std.mem.eql(u8, format, "value")) {
        if (show_tag) |tag| {
            const val = if (std.mem.eql(u8, tag, "UUID")) info.uuid else if (std.mem.eql(u8, tag, "TYPE")) info.fstype else if (std.mem.eql(u8, tag, "LABEL")) info.label else "";
            if (val.len > 0) {
                core.writeAll(1, val);
                core.writeAll(1, "\n");
            }
        }
    } else {
        // full (default)
        if (info.fstype.len == 0) return;
        var buf: [1024]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "/dev/{s}: UUID=\"{s}\" TYPE=\"{s}\" LABEL=\"{s}\"\n", .{ name, info.uuid, info.fstype, info.label }) catch return;
        core.writeAll(1, out);
    }
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var show_tag: ?[]const u8 = null;
    var format: []const u8 = "full";
    var device_specified = false;
    var device: []const u8 = "";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-s") and i + 1 < args.len) {
            i += 1;
            show_tag = args[i];
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            format = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "blkid: invalid option '{s}'\n", .{arg});
        } else {
            device = arg;
            device_specified = true;
        }
    }

    if (device_specified) {
        var path_buf: [4096:0]u8 = undefined;
        const dev_path = if (std.mem.startsWith(u8, device, "/dev/")) device else blk: {
            const p = std.fmt.bufPrint(&path_buf, "/dev/{s}", .{device}) catch return 1;
            @memcpy(path_buf[0..p.len], p);
            path_buf[p.len] = 0;
            break :blk path_buf[0..p.len :0];
        };
        const fd = core.c.open(dev_path.ptr, core.c.O_RDONLY);
        if (fd < 0) return core.die(1, "blkid: cannot open {s}\n", .{dev_path});
        defer _ = core.c.close(fd);
        const info = getFsInfo(fd);
        const name = std.fs.path.basename(dev_path);
        showDevice(name, info, show_tag, format);
        return 0;
    }

    // No device specified: read /proc/partitions
    const fd = core.c.open("/proc/partitions", core.c.O_RDONLY);
    if (fd < 0) return 1;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1024 * 64) catch return 1;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next(); // skip header
    _ = lines.next(); // skip header

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

        var dev_path_buf: [4096:0]u8 = undefined;
        const dev_path = std.fmt.bufPrint(&dev_path_buf, "/dev/{s}", .{name}) catch continue;
        @memcpy(dev_path_buf[0..dev_path.len], dev_path);
        dev_path_buf[dev_path.len] = 0;
        const dfd = core.c.open(dev_path_buf[0..dev_path.len :0].ptr, core.c.O_RDONLY);
        if (dfd < 0) continue;
        defer _ = core.c.close(dfd);
        const info = getFsInfo(dfd);
        showDevice(name, info, show_tag, format);
    }

    return 0;
}
