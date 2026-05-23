const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "rpm2cpio", .main = main };

fn readAllFd(alloc: std.mem.Allocator, fd: c_int) ![]u8 {
    return core.readAll(alloc, fd, 1 << 28);
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "rpm2cpio: usage: rpm2cpio FILE.rpm\n", .{});

    const file = args[1];
    var path_buf: [4096:0]u8 = undefined;
    if (file.len >= path_buf.len) return 1;
    @memcpy(path_buf[0..file.len], file);
    path_buf[file.len] = 0;

    const fd = core.c.open(path_buf[0..file.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "rpm2cpio: cannot open '{s}'\n", .{file});
    defer _ = core.c.close(fd);

    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, fd) catch return 1;
    defer alloc.free(data);

    if (data.len < 96) return core.die(1, "rpm2cpio: file too small\n", .{});

    const rpm_magic = data[0..4];
    if (!std.mem.eql(u8, rpm_magic, "\xed\xab\xee\xdb")) return core.die(1, "rpm2cpio: not an RPM file\n", .{});

    var pos: usize = 96;

    while (pos < data.len) {
        if (pos + 4 > data.len) break;
        const magic = data[pos..pos+4];
        if (std.mem.eql(u8, magic, "0707")) {
            break;
        }
        pos += 1;
    }

    if (pos >= data.len) return core.die(1, "rpm2cpio: no cpio archive found\n", .{});

    core.writeAll(1, data[pos..]);

    return 0;
}
