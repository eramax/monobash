const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "xargs", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;

    const cmd = args[1];
    var z_cmd_buf: [4096:0]u8 = undefined;
    if (cmd.len >= z_cmd_buf.len) return 1;
    @memcpy(z_cmd_buf[0..cmd.len], cmd);
    z_cmd_buf[cmd.len] = 0;

    var reader = core.LineReader.init(0);
    var rc: u8 = 0;

    while (reader.next()) |line| {
        var arg_buf: [4096:0]u8 = undefined;
        if (line.len >= arg_buf.len) { rc = 1; continue; }
        @memcpy(arg_buf[0..line.len], line);
        arg_buf[line.len] = 0;

        var argv_list: [3][*c]u8 = undefined;
        argv_list[0] = z_cmd_buf[0..cmd.len :0].ptr;
        argv_list[1] = arg_buf[0..line.len :0].ptr;
        argv_list[2] = null;

        const pid = core.c.fork();
        if (pid < 0) return 1;
        if (pid == 0) {
            _ = core.c.execvp(argv_list[0], &argv_list);
            core.c._exit(127);
        }
        var wstatus: c_int = 0;
        while (core.c.waitpid(pid, &wstatus, 0) < 0) {}
        if (core.c.WIFEXITED(@as(c_int, @intCast(wstatus)))) {
            const code = core.c.WEXITSTATUS(@as(c_int, @intCast(wstatus)));
            if (code != 0) rc = @as(u8, @intCast(code));
        } else {
            rc = 1;
        }
    }

    return rc;
}
