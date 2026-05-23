const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lzop", .main = main };

fn compressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var child = std.process.Child.init(&[_][]const u8{ "lzop" }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return core.die(1, "lzop: cannot spawn lzop\n", .{});
    child.stdin.?.writeAll(data) catch {
        _ = child.wait();
        return core.die(1, "lzop: write error\n", .{});
    };
    child.stdin.?.close();
    const output = child.stdout.?.reader().readAllAlloc(alloc, 1 << 28) catch {
        _ = child.wait();
        return core.die(1, "lzop: read error\n", .{});
    };
    defer alloc.free(output);
    _ = child.wait() catch {};
    core.writeAll(out_fd, output);
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var file_arg: ?[]const u8 = null;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            _ = c;
            return core.die(1, "lzop: not implemented (no lzop in Zig std lib)\n", .{});
        }
        i += 1;
    }
    if (i < args.len) file_arg = args[i];

    const alloc = std.heap.page_allocator;
    if (file_arg) |file| {
        const fd = core.openReadName(file) orelse return core.die(1, "lzop: cannot open '{s}'\n", .{file});
        defer _ = core.c.close(fd);
        const data = core.readAll(alloc, fd, 1 << 28) catch return 1;
        defer alloc.free(data);
        var buf: [4096:0]u8 = undefined;
        if (file.len + 4 >= buf.len) return 1;
        @memcpy(buf[0..file.len], file);
        buf[file.len..][0..4].* = ".lzo".*;
        buf[file.len + 4] = 0;
        const out_fd = core.c.open(buf[0..file.len + 4 :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
        if (out_fd < 0) return 1;
        defer _ = core.c.close(out_fd);
        return compressToFd(data, out_fd);
    } else {
        const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
        defer alloc.free(data);
        return compressToFd(data, 1);
    }
}
