const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "bzcat", .main = main };

fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var child = std.process.Child.init(&[_][]const u8{ "bzip2", "-d", "-c" }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return core.die(1, "bzcat: cannot spawn bzip2\n", .{});
    child.stdin.?.writeAll(data) catch {
        _ = child.wait();
        return core.die(1, "bzcat: write error\n", .{});
    };
    child.stdin.?.close();
    const output = child.stdout.?.reader().readAllAlloc(alloc, 1 << 28) catch {
        _ = child.wait();
        return core.die(1, "bzcat: read error\n", .{});
    };
    defer alloc.free(output);
    _ = child.wait() catch {};
    core.writeAll(out_fd, output);
    return 0;
}

fn decompressFile(name: []const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.openReadName(name) orelse {
        return core.die(1, "bzcat: cannot open '{s}'\n", .{name});
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
        return core.die(1, "bzcat: unknown option\n", .{});
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
