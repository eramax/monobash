const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "lzma", .main = main };

fn compressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var child = std.process.Child.init(&[_][]const u8{ "lzma", "-z" }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return core.die(1, "lzma: cannot spawn lzma\n", .{});
    child.stdin.?.writeAll(data) catch {
        _ = child.wait();
        return core.die(1, "lzma: write error\n", .{});
    };
    child.stdin.?.close();
    const output = child.stdout.?.reader().readAllAlloc(alloc, 1 << 28) catch {
        _ = child.wait();
        return core.die(1, "lzma: read error\n", .{});
    };
    defer alloc.free(output);
    _ = child.wait() catch {};
    core.writeAll(out_fd, output);
    return 0;
}

fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var child = std.process.Child.init(&[_][]const u8{ "lzma", "-d" }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return core.die(1, "lzma: cannot spawn lzma\n", .{});
    child.stdin.?.writeAll(data) catch {
        _ = child.wait();
        return core.die(1, "lzma: write error\n", .{});
    };
    child.stdin.?.close();
    const output = child.stdout.?.reader().readAllAlloc(alloc, 1 << 28) catch {
        _ = child.wait();
        return core.die(1, "lzma: read error\n", .{});
    };
    defer alloc.free(output);
    _ = child.wait() catch {};
    core.writeAll(out_fd, output);
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    var decompress = false;
    var file_arg: ?[]const u8 = null;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |c| {
            switch (c) {
                'd' => decompress = true,
                else => return core.die(1, "lzma: unknown option '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    if (i < args.len) file_arg = args[i];

    const alloc = std.heap.page_allocator;
    if (decompress) {
        if (file_arg) |file| {
            const fd = core.openReadName(file) orelse return core.die(1, "lzma: cannot open '{s}'\n", .{file});
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 1 << 28) catch return 1;
            defer alloc.free(data);
            var out_name = file;
            if (std.mem.endsWith(u8, file, ".lzma")) {
                out_name = file[0 .. file.len - 5];
            }
            var buf: [4096:0]u8 = undefined;
            if (out_name.len >= buf.len) return 1;
            @memcpy(buf[0..out_name.len], out_name);
            buf[out_name.len] = 0;
            const out_fd = core.c.open(buf[0..out_name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (out_fd < 0) return 1;
            defer _ = core.c.close(out_fd);
            return decompressToFd(data, out_fd);
        } else {
            const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
            defer alloc.free(data);
            return decompressToFd(data, 1);
        }
    } else {
        if (file_arg) |file| {
            const fd = core.openReadName(file) orelse return core.die(1, "lzma: cannot open '{s}'\n", .{file});
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 1 << 28) catch return 1;
            defer alloc.free(data);
            var buf: [4096:0]u8 = undefined;
            if (file.len + 5 >= buf.len) return 1;
            @memcpy(buf[0..file.len], file);
            buf[file.len..][0..5].* = ".lzma".*;
            buf[file.len + 5] = 0;
            const out_fd = core.c.open(buf[0..file.len + 5 :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (out_fd < 0) return 1;
            defer _ = core.c.close(out_fd);
            return compressToFd(data, out_fd);
        } else {
            const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
            defer alloc.free(data);
            return compressToFd(data, 1);
        }
    }
}
