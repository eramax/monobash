const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "xzcat", .main = main };

fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var source = std.Io.Reader.fixed(data);
    const buf = alloc.alloc(u8, 65536) catch return 1;
    defer alloc.free(buf);
    var decomp = std.compress.xz.Decompress.init(&source, alloc, buf) catch {
        return core.die(1, "xzcat: decompression failed\n", .{});
    };
    defer decomp.deinit();
    const result = decomp.reader.allocRemaining(alloc, .{}) catch {
        return core.die(1, "xzcat: decompression failed\n", .{});
    };
    defer alloc.free(result);
    core.writeAll(out_fd, result);
    return 0;
}

fn decompressFile(name: []const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.openReadName(name) orelse {
        return core.die(1, "xzcat: cannot open '{s}'\n", .{name});
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
        return core.die(1, "xzcat: unknown option\n", .{});
    }
    if (i >= args.len) {
        const alloc = std.heap.page_allocator;
        const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
        defer alloc.free(data);
        return decompressToFd(data, 1);
    }
    var rc: u8 = 0;
    while (i < args.len) {
        rc |= decompressFile(args[i]);
        i += 1;
    }
    return rc;
}
