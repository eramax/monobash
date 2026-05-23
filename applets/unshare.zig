const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "unshare", .main = main };

const CLONE_NEWNS: c_uint = 0x00020000;
const CLONE_NEWUTS: c_uint = 0x04000000;
const CLONE_NEWIPC: c_uint = 0x08000000;
const CLONE_NEWUSER: c_uint = 0x10000000;
const CLONE_NEWPID: c_uint = 0x20000000;
const CLONE_NEWNET: c_uint = 0x40000000;

pub fn main(args: [][]const u8) u8 {
    var flags: c_uint = 0;
    var map_root = false;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-r")) {
            map_root = true;
        } else if (std.mem.eql(u8, arg, "-n")) {
            flags |= CLONE_NEWNET;
        } else if (std.mem.eql(u8, arg, "-m")) {
            flags |= CLONE_NEWNS;
        } else if (std.mem.eql(u8, arg, "-u")) {
            flags |= CLONE_NEWUTS;
        } else if (std.mem.eql(u8, arg, "-i")) {
            flags |= CLONE_NEWIPC;
        } else if (std.mem.eql(u8, arg, "-p")) {
            flags |= CLONE_NEWPID;
        } else if (arg.len > 0 and arg[0] == '-') {
            return core.die(1, "usage: unshare [-r] [-n] [-m] [-u] [-i] [-p] CMD...\n", .{});
        } else {
            break;
        }
    }

    if (i >= args.len) return core.die(1, "usage: unshare [-r] [-n] [-m] [-u] [-i] [-p] CMD...\n", .{});

    // Fork first for PID namespace support
    const pid = core.c.fork();
    if (pid < 0) return 1;

    if (pid == 0) {
        // Child: unshare and exec
        if (core.c.unshare(@as(c_int, @intCast(flags))) < 0) {
            core.writeAll(2, "unshare: failed\n");
            core.c._exit(1);
        }

        if (map_root) {
            // Write uid/gid mappings for user namespace
            var uid: [32]u8 = undefined;
            var gid: [32]u8 = undefined;
            const uid_str = std.fmt.bufPrint(&uid, "0 {d} 1\n", .{core.c.getuid()}) catch "";
            const gid_str = std.fmt.bufPrint(&gid, "0 {d} 1\n", .{core.c.getgid()}) catch "";

            const uid_fd = core.c.open("/proc/self/uid_map", core.c.O_WRONLY);
            if (uid_fd >= 0) {
                core.writeAll(uid_fd, uid_str);
                _ = core.c.close(uid_fd);
            }
            const setgroups_fd = core.c.open("/proc/self/setgroups", core.c.O_WRONLY);
            if (setgroups_fd >= 0) {
                core.writeAll(setgroups_fd, "deny");
                _ = core.c.close(setgroups_fd);
            }
            const gid_fd = core.c.open("/proc/self/gid_map", core.c.O_WRONLY);
            if (gid_fd >= 0) {
                core.writeAll(gid_fd, gid_str);
                _ = core.c.close(gid_fd);
            }
        }

        const alloc = std.heap.page_allocator;
        const argc = args.len - i;
        const c_argv = alloc.alloc([*c]u8, argc + 1) catch core.c._exit(127);
        for (args[i..], 0..) |arg, j| {
            c_argv[j] = (alloc.dupeZ(u8, arg) catch core.c._exit(127)).ptr;
        }
        c_argv[argc] = null;

        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }

    var wstatus: c_int = 0;
    _ = core.c.waitpid(pid, &wstatus, 0);
    if (core.c.WIFEXITED(wstatus)) return @intCast(core.c.WEXITSTATUS(wstatus));
    return 1;
}
