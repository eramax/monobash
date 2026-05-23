const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "uncompress", .main = main };

fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const alloc = std.heap.page_allocator;
    var child = std.process.Child.init(&[_][]const u8{ "zcat" }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return core.die(1, "uncompress: cannot spawn zcat\n", .{});
    child.stdin.?.writeAll(data) catch {
        _ = child.wait();
        return core.die(1, "uncompress: write error\n", .{});
    };
    child.stdin.?.close();
    const output = child.stdout.?.reader().readAllAlloc(alloc, 1 << 28) catch {
        _ = child.wait();
        return core.die(1, "uncompress: read error\n", .{});
    };
    defer alloc.free(output);
    _ = child.wait() catch {};
    core.writeAll(out_fd, output);
    return 0;
}

pub fn main(args: [][]const u8) u8 {
    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "--")) {
        i += 1;
        break;
    } else if (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        return core.die(1, "uncompress: unknown option\n", .{});
    }
    const alloc = std.heap.page_allocator;
    if (i >= args.len) {
        const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
        defer alloc.free(data);
        return decompressToFd(data, 1);
    }
    var rc: u8 = 0;
    while (i < args.len) {
        const file = args[i];
        i += 1;
        const fd = core.openReadName(file) orelse {
            rc |= core.die(1, "uncompress: cannot open '{s}'\n", .{file});
            continue;
        };
        defer _ = core.c.close(fd);
        const data = core.readAll(alloc, fd, 1 << 28) catch {
            rc |= 1;
            continue;
        };
        defer alloc.free(data);
        var out_name = file;
        if (std.mem.endsWith(u8, file, ".Z")) {
            out_name = file[0 .. file.len - 2];
        }
        var buf: [4096:0]u8 = undefined;
        if (out_name.len >= buf.len) { rc |= 1; continue; }
        @memcpy(buf[0..out_name.len], out_name);
        buf[out_name.len] = 0;
        const out_fd = core.c.open(buf[0..out_name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
        if (out_fd < 0) { rc |= 1; continue; }
        defer _ = core.c.close(out_fd);
        rc |= decompressToFd(data, out_fd);
    }
    return rc;
}
