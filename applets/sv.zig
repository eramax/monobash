const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "sv", .main = main };

const alloc = std.heap.page_allocator;

pub fn main(args: [][]const u8) u8 {
    if (args.len < 3) return core.die(1, "usage: sv (status|up|down|restart|hup) SERVICE\n", .{});

    const cmd = args[1];
    const svc = args[2];

    var supervise_path_buf: [4096]u8 = undefined;
    const sup_path = std.fmt.bufPrint(&supervise_path_buf, "{s}/supervise", .{svc}) catch return 1;

    var status_path_buf: [4096]u8 = undefined;
    const status_path = std.fmt.bufPrint(&status_path_buf, "{s}/supervise/status", .{svc}) catch return 1;

    var control_path_buf: [4096]u8 = undefined;
    const control_path = std.fmt.bufPrint(&control_path_buf, "{s}/supervise/control", .{svc}) catch return 1;

    var z_buf: [4096:0]u8 = undefined;

    if (std.mem.eql(u8, cmd, "status")) {
        @memcpy(z_buf[0..sup_path.len], sup_path);
        z_buf[sup_path.len] = 0;
        var st1: core.c.struct_stat = undefined;
        if (core.c.stat(&z_buf, &st1) != 0) {
            return core.die(1, "sv: {s}: supervise directory not found\n", .{svc});
        }

        @memcpy(z_buf[0..status_path.len], status_path);
        z_buf[status_path.len] = 0;
        var st2: core.c.struct_stat = undefined;
        if (core.c.stat(&z_buf, &st2) != 0) {
            core.writeAll(1, "down: ");
            core.writeAll(1, svc);
            core.writeAll(1, ": not running\n");
            return 0;
        }

        @memcpy(z_buf[0..status_path.len], status_path);
        z_buf[status_path.len] = 0;
        const fd = core.c.open(&z_buf, core.c.O_RDONLY);
        if (fd < 0) {
            return core.die(1, "sv: {s}: cannot open status\n", .{svc});
        }
        defer _ = core.c.close(fd);

        var status_data: [20]u8 = undefined;
        const n = core.c.read(fd, @as([*c]u8, @ptrCast(&status_data)), status_data.len);
        if (n < 3) {
            core.writeAll(1, svc);
            core.writeAll(1, ": unknown\n");
            return 0;
        }

        const state = status_data[0];
        const svc_pid: u32 = @intCast(@as(u32, @intCast(status_data[1])) |
            (@as(u32, @intCast(status_data[2])) << 8) |
            (@as(u32, @intCast(status_data[3])) << 16) |
            (@as(u32, @intCast(status_data[4])) << 24));

        if (state == 'u') {
            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "run: {s}: pid={d}\n", .{ svc, svc_pid }) catch return 1;
            core.writeAll(1, line);
        } else if (state == 'd') {
            const exit_code: u32 = if (n >= 8)
                @intCast(@as(u32, @intCast(status_data[5])) |
                    (@as(u32, @intCast(status_data[6])) << 8) |
                    (@as(u32, @intCast(status_data[7])) << 16) |
                    (@as(u32, @intCast(status_data[8])) << 24))
            else
                0;
            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "down: {s}: exit={d}\n", .{ svc, exit_code }) catch return 1;
            core.writeAll(1, line);
        } else {
            core.writeAll(1, svc);
            core.writeAll(1, ": unknown\n");
        }

        return 0;
    }

    const ctrl_char: u8 = if (std.mem.eql(u8, cmd, "up")) 'u' else if (std.mem.eql(u8, cmd, "down")) 'd' else if (std.mem.eql(u8, cmd, "restart")) 'r' else if (std.mem.eql(u8, cmd, "hup")) 'h' else 0;
    if (ctrl_char == 0) return core.die(1, "sv: unknown command '{s}'\n", .{cmd});

    @memcpy(z_buf[0..control_path.len], control_path);
    z_buf[control_path.len] = 0;
    const fd = core.c.open(&z_buf, core.c.O_WRONLY | core.c.O_NONBLOCK);
    if (fd < 0) return core.die(1, "sv: cannot open {s}/supervise/control\n", .{svc});
    defer _ = core.c.close(fd);

    const ctrl_byte = [1]u8{ctrl_char};
    const wrote = core.c.write(fd, @as([*c]u8, @ptrCast(&ctrl_byte)), 1);
    if (wrote < 0) return core.die(1, "sv: cannot send command to {s}\n", .{svc});

    return 0;
}
