const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "gunzip", .main = main };

fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var source = std.Io.Reader.fixed(data);
    const buf = alloc.alloc(u8, 65536) catch return 1;
    defer alloc.free(buf);
    var decomp = std.compress.flate.Decompress.init(&source, .gzip, buf);
    const result = decomp.reader.allocRemaining(alloc, .{}) catch {
        return core.die(1, "gunzip: decompression failed\n", .{});
    };
    defer alloc.free(result);
    core.writeAll(out_fd, result);
    return 0;
}

fn decompressFile(name: []const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.openReadName(name) orelse {
        return core.die(1, "gunzip: cannot open '{s}'\n", .{name});
    };
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1 << 28) catch return 1;
    defer alloc.free(data);
    return decompressToFd(data, 1);
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "--")) {
        i += 1;
        break;
    } else if (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        return core.die(1, "gunzip: unknown option\n", .{});
    }
    if (i >= args.len)
        return decompressToFd(core.readAll(std.heap.page_allocator, 0, 1 << 28) catch return 1, 1);
    var rc: u8 = 0;
    while (i < args.len) {
        rc |= decompressFile(args[i]);
        i += 1;
    }
    return rc;
}
