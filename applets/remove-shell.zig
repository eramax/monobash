const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "remove-shell", .main = main };

const shells_file = "/etc/shells";

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: remove-shell SHELL...\n", .{});

    const alloc = std.heap.page_allocator;

    const orig_fn_z = alloc.dupeZ(u8, shells_file) catch return 1;
    const orig_fd = core.c.open(orig_fn_z.ptr, core.c.O_RDONLY);
    var st: core.c.struct_stat = undefined;
    st.st_mode = 0o666;
    if (orig_fd >= 0) {
        _ = core.c.fstat(orig_fd, &st);
    }

    const tmp_fn = std.fmt.allocPrint(alloc, "{s}.tmp", .{shells_file}) catch return 1;
    defer alloc.free(tmp_fn);
    const tmp_fn_z = alloc.dupeZ(u8, tmp_fn) catch return 1;

    const oflags = core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC;
    const out_fd = core.c.open(tmp_fn_z.ptr, oflags, @as(c_uint, @intCast(st.st_mode)));
    if (out_fd < 0) return core.die(1, "remove-shell: cannot create temp file\n", .{});

    const saved_out = core.c.dup(1);
    _ = core.c.dup2(out_fd, 1);
    _ = core.c.close(out_fd);

    if (orig_fd >= 0) {
        var reader = core.LineReader.init(orig_fd);
        while (reader.next()) |line| {
            var skip = false;
            for (args[1..]) |shell| {
                if (std.mem.eql(u8, line, shell)) {
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                core.writeAll(1, line);
                core.writeAll(1, "\n");
            }
        }
        _ = core.c.close(orig_fd);
    }

    _ = core.c.dup2(saved_out, 1);
    _ = core.c.close(saved_out);

    if (core.c.rename(tmp_fn_z.ptr, orig_fn_z.ptr) < 0) {
        _ = core.c.unlink(tmp_fn_z.ptr);
        return core.die(1, "remove-shell: rename failed\n", .{});
    }

    return 0;
}
