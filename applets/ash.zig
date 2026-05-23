const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ash", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    var line_buf: [4096]u8 = undefined;

    while (true) {
        _ = core.c.write(1, "$ ", 2);
        var pos: usize = 0;
        while (pos < line_buf.len) {
            var ch: u8 = 0;
            const n = core.c.read(0, @as([*]u8, @ptrCast(&ch)), 1);
            if (n <= 0) return 0;
            if (ch == '\n') break;
            line_buf[pos] = ch;
            pos += 1;
        }
        if (pos == 0) continue;
        const line = line_buf[0..pos];

        if (std.mem.eql(u8, line, "exit")) return 0;

        if (std.mem.startsWith(u8, line, "cd ")) {
            const dir = std.mem.trim(u8, line[3..], " \t");
            var zbuf: [4096:0]u8 = undefined;
            if (dir.len >= zbuf.len) {
                _ = core.c.write(2, "cd: path too long\n", 18);
                continue;
            }
            @memcpy(zbuf[0..dir.len], dir);
            zbuf[dir.len] = 0;
            if (core.c.chdir(zbuf[0..dir.len :0].ptr) < 0) {
                _ = core.c.write(2, "cd: ", 4);
                _ = core.c.write(2, dir.ptr, dir.len);
                _ = core.c.write(2, ": ", 2);
                _ = core.c.write(2, "No such file or directory\n", 26);
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "export ")) {
            const rest = std.mem.trim(u8, line[7..], " \t");
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
                var name_buf: [256:0]u8 = undefined;
                var val_buf: [4096:0]u8 = undefined;
                const name = rest[0..eq];
                const val = rest[eq + 1 ..];
                if (name.len < name_buf.len and val.len < val_buf.len) {
                    @memcpy(name_buf[0..name.len], name);
                    name_buf[name.len] = 0;
                    @memcpy(val_buf[0..val.len], val);
                    val_buf[val.len] = 0;
                    _ = core.c.setenv(name_buf[0..name.len :0].ptr, val_buf[0..val.len :0].ptr, 1);
                }
            }
            continue;
        }

        var argv_buf: [64][]const u8 = undefined;
        var argc: usize = 0;
        var start: usize = 0;
        while (start < line.len) {
            while (start < line.len and (line[start] == ' ' or line[start] == '\t')) : (start += 1) {}
            if (start >= line.len) break;
            var end = start;
            while (end < line.len and line[end] != ' ' and line[end] != '\t') : (end += 1) {}
            if (argc < argv_buf.len) {
                argv_buf[argc] = line[start..end];
                argc += 1;
            }
            start = end;
        }
        if (argc == 0) continue;

        const alloc = std.heap.page_allocator;
        const c_argv = alloc.alloc([*c]u8, argc + 1) catch continue;
        for (argv_buf[0..argc], 0..) |arg, i| {
            const arg_z = alloc.dupeZ(u8, arg) catch continue;
            c_argv[i] = arg_z.ptr;
        }
        c_argv[argc] = null;

        const pid = core.c.fork();
        if (pid < 0) {
            alloc.free(c_argv);
            _ = core.c.write(2, "fork failed\n", 12);
            continue;
        }
        if (pid == 0) {
            _ = core.c.execvp(c_argv[0], c_argv.ptr);
            _ = core.c.write(2, c_argv[0], std.mem.len(c_argv[0]));
            _ = core.c.write(2, ": command not found\n", 20);
            core.c._exit(127);
        }
        var wstatus: c_int = 0;
        _ = core.c.waitpid(pid, &wstatus, 0);
    }
}
