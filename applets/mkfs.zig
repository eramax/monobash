const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "mkfs", .main = main };

extern "c" fn fork() c_int;
extern "c" fn execvp(path: [*c]u8, argv: [*c][*c]u8) c_int;
extern "c" fn waitpid(pid: c_int, wstatus: *c_int, options: c_int) c_int;

fn c_wifexited(status: c_int) bool {
    return (status & 0x7f) == 0;
}

fn c_wexitstatus(status: c_int) u8 {
    return @intCast((status >> 8) & 0xff);
}

pub fn main(args: [][]const u8) u8 {
    var fstype: []const u8 = "ext4";
    var device: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-t") and i + 1 < args.len) {
            i += 1;
            fstype = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return core.die(1, "mkfs: invalid option '{s}'\n", .{arg});
        } else {
            device = arg;
        }
    }

    const dev = device orelse return core.die(1, "mkfs: usage: mkfs -t TYPE DEVICE\n", .{});

    var prog_buf: [128]u8 = undefined;
    const prog = std.fmt.bufPrint(&prog_buf, "mkfs.{s}", .{fstype}) catch return 1;
    var prog_z: [128]u8 = undefined;
    @memcpy(prog_z[0..prog.len], prog);
    prog_z[prog.len] = 0;

    var dev_buf: [4096:0]u8 = undefined;
    const dev_z = if (std.mem.startsWith(u8, dev, "/dev/")) dev else blk: {
        const p = std.fmt.bufPrint(&dev_buf, "/dev/{s}", .{dev}) catch return 1;
        @memcpy(dev_buf[0..p.len], p);
        dev_buf[p.len] = 0;
        break :blk dev_buf[0..p.len :0];
    };

    const pid = fork();
    if (pid < 0) return core.die(1, "mkfs: fork failed\n", .{});

    if (pid == 0) {
        // Child process
        const argv = [_][*c]u8{ @as([*c]u8, @ptrCast(@constCast(&prog_z))), @as([*c]u8, @ptrCast(@constCast(&dev_z))), null };
        _ = execvp(@as([*c]u8, @ptrCast(&prog_z)), @as([*c][*c]u8, @ptrCast(&argv)));
        // If exec fails
        core.writeAll(2, "mkfs: exec failed\n");
        std.process.exit(127);
    }

    var wstatus: c_int = 0;
    _ = waitpid(pid, &wstatus, 0);

    if (c_wifexited(wstatus)) {
        return c_wexitstatus(wstatus);
    }
    return 1;
}
