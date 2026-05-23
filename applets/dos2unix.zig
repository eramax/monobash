const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "dos2unix", .main = main };

pub fn main(args: [][]const u8) u8 {
    var to_unix = true;
    var file_arg: ?[]const u8 = null;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-u")) {
            to_unix = true;
        } else if (std.mem.eql(u8, arg, "-d")) {
            to_unix = false;
        } else if (arg.len > 0 and arg[0] != '-') {
            file_arg = arg;
        } else {
            return core.die(1, "usage: dos2unix [-u|-d] FILE\n", .{});
        }
    }

    const file = file_arg orelse return core.die(1, "usage: dos2unix [-u|-d] FILE\n", .{});

    var zpath: [4096:0]u8 = undefined;
    if (file.len >= zpath.len) return 1;
    @memcpy(zpath[0..file.len], file);
    zpath[file.len] = 0;

    const fd = core.c.open(zpath[0..file.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "dos2unix: cannot open {s}\n", .{file});

    var buf: [65536]u8 = undefined;
    const n = core.c.read(fd, @as([*]u8, @ptrCast(&buf)), buf.len);
    _ = core.c.close(fd);
    if (n <= 0) return 0;

    const data = buf[0..@intCast(n)];
    var out_buf: [65536]u8 = undefined;
    var out_len: usize = 0;

    if (to_unix) {
        // CRLF -> LF
        var j: usize = 0;
        while (j < data.len) : (j += 1) {
            if (data[j] == '\r' and j + 1 < data.len and data[j + 1] == '\n') {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = '\n';
                    out_len += 1;
                }
                j += 1;
            } else {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = data[j];
                    out_len += 1;
                }
            }
        }
    } else {
        // LF -> CRLF
        var j: usize = 0;
        while (j < data.len) : (j += 1) {
            if (data[j] == '\n') {
                if (out_len + 2 <= out_buf.len) {
                    out_buf[out_len] = '\r';
                    out_buf[out_len + 1] = '\n';
                    out_len += 2;
                }
            } else {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = data[j];
                    out_len += 1;
                }
            }
        }
    }

    const wfd = core.c.open(zpath[0..file.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (wfd < 0) return core.die(1, "dos2unix: cannot write {s}\n", .{file});
    defer _ = core.c.close(wfd);

    _ = core.c.write(wfd, @as([*]u8, @ptrCast(&out_buf)), @intCast(out_len));

    return 0;
}
