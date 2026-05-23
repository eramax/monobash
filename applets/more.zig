const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "more", .main = main };

pub fn main(args: [][]const u8) u8 {
    var do_prompt = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'd' => do_prompt = true,
                else => return core.die(1, "more: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    const files = args[i..];
    var exit_code: u8 = 0;

    if (files.len == 0) {
        const data = core.readAll(std.heap.page_allocator, 0, 1024 * 1024) catch return 1;
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
        return 0;
    }

    for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("more: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("more: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);

        if (files.len > 1) {
            var hbuf: [4096]u8 = undefined;
            const h = std.fmt.bufPrint(&hbuf, "::::::::::::::\n{s}\n::::::::::::::\n", .{f}) catch "";
            core.writeAll(1, h);
        }

        if (do_prompt) {
            core.writeAll(1, "--More--(Next file: ");
            core.writeAll(1, f);
            core.writeAll(1, ")");
        }

        const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch {
            exit_code = 1;
            continue;
        };
        defer std.heap.page_allocator.free(data);
        core.writeAll(1, data);
    }

    return exit_code;
}
