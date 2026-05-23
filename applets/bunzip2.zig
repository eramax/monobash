const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "bunzip2", .main = main };
fn pipeThrough(in_data: []const u8, cmd: []const u8) ![]u8 {
    const alloc = std.heap.page_allocator;
    var to_child: [2]c_int = undefined;
    var from_child: [2]c_int = undefined;
    if (core.c.pipe(&to_child) < 0 or core.c.pipe(&from_child) < 0) return error.PipeFail;
    const pid = core.c.fork();
    if (pid < 0) return error.ForkFail;
    if (pid == 0) {
        _ = core.c.close(to_child[1]); _ = core.c.close(from_child[0]);
        _ = core.c.dup2(to_child[0], 0); _ = core.c.dup2(from_child[1], 1);
        const argv = [_][*c]u8{ cmd, null };
        _ = core.c.execvp(cmd, &argv);
        core.c._exit(1);
    }
    _ = core.c.close(to_child[0]); _ = core.c.close(from_child[1]);
    var pos: usize = 0;
    while (pos < in_data.len) { const n = core.c.write(to_child[1], in_data.ptr + pos, in_data.len - pos); if (n <= 0) break; pos += @intCast(n); }
    _ = core.c.close(to_child[1]);
    var buf = alloc.alloc(u8, 65536) catch return error.NoMem;
    var total: usize = 0;
    while (true) {
        if (total >= buf.len) buf = alloc.realloc(buf, buf.len * 2) catch return error.NoMem;
        const n = core.c.read(from_child[0], buf.ptr + total, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    _ = core.c.close(from_child[0]);
    _ = core.c.waitpid(pid, null, 0);
    return buf[0..total];
}
fn decompressToFd(data: []const u8, out_fd: c_int) u8 {
    const out = pipeThrough(data, "bzip2") catch return core.die(1, "bunzip2: decompress failed\n", .{});
    defer std.heap.page_allocator.free(out);
    core.writeAll(out_fd, out);
    return 0;
}
fn decompressFile(name: []const u8) u8 {
    const alloc = std.heap.page_allocator;
    const fd = core.openReadName(name) orelse return core.die(1, "bunzip2: cannot open '{s}'\n", .{name});
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 1 << 28) catch return 1;
    defer alloc.free(data);
    var out_name = if (std.mem.endsWith(u8, name, ".bz2")) name[0 .. name.len - 4] else name;
    var buf: [4096:0]u8 = undefined;
    if (out_name.len >= buf.len) return 1;
    @memcpy(buf[0..out_name.len], out_name);
    buf[out_name.len] = 0;
    const out_fd = core.c.open(buf[0..out_name.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (out_fd < 0) return 1;
    defer _ = core.c.close(out_fd);
    return decompressToFd(data, out_fd);
}
pub fn main(args: [][]const u8) u8 {
    if (args.len <= 1) {
        const alloc = std.heap.page_allocator;
        const data = core.readAll(alloc, 0, 1 << 28) catch return 1;
        defer alloc.free(data);
        return decompressToFd(data, 1);
    }
    var rc: u8 = 0;
    for (args[1..]) |f| rc |= decompressFile(f);
    return rc;
}
