const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "which", .main = main };

const builtins = [_][]const u8{
    "alias", "bg", "cd", "command", "echo", "eval", "exec",
    "exit", "export", "fg", "fc", "getopts", "hash", "jobs",
    "kill", "let", "local", "printf", "pwd", "read", "readonly",
    "return", "set", "shift", "source", "test", "times", "trap",
    "type", "ulimit", "umask", "unalias", "unset", "wait",
};

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return 1;
    var exit_code: u8 = 0;
    for (args[1..]) |name| {
        var found = false;
        for (builtins) |b| {
            if (std.mem.eql(u8, name, b)) {
                core.writeAll(1, "builtin\n");
                found = true;
                break;
            }
        }
        if (found) continue;
        if (isApplet(name)) {
            core.writeAll(1, "applet\n");
        } else if (findInPath(name)) |path| {
            core.writeAll(1, path);
            core.writeAll(1, "\n");
            std.heap.page_allocator.free(path);
        } else {
            exit_code = 1;
        }
    }
    return exit_code;
}

fn isApplet(name: []const u8) bool {
    const applet_names = [_][]const u8{
        "true", "false", "cat", "yes", "sleep", "ln", "chmod",
        "chown", "uname", "hostname", "env", "printenv",
        "basename", "dirname", "whoami", "id", "which",
    };
    for (applet_names) |a| {
        if (std.mem.eql(u8, name, a)) return true;
    }
    return false;
}

fn findInPath(name: []const u8) ?[]u8 {
    const path_env = core.c.getenv("PATH") orelse return null;
    const path_str = std.mem.sliceTo(path_env, 0);
    var it = std.mem.splitScalar(u8, path_str, ':');
    while (it.next()) |dir| {
        var full: [4096:0]u8 = undefined;
        const total = dir.len + 1 + name.len;
        if (total + 1 >= full.len) continue;
        @memcpy(full[0..dir.len], dir);
        full[dir.len] = '/';
        @memcpy(full[dir.len + 1 ..][0..name.len], name);
        full[total] = 0;
        if (core.c.access(&full, core.c.X_OK) == 0) {
            return std.heap.page_allocator.dupe(u8, full[0..total]) catch null;
        }
    }
    return null;
}
