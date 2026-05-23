const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "taskset", .main = main };

const CPU_SETSIZE = 1024;
const word_type = usize;
const word_bits = @bitSizeOf(word_type);
const num_words = CPU_SETSIZE / word_bits;

const hex_chars = "0123456789abcdef";

fn printMask(mask: *const core.c.cpu_set_t) void {
    var started = false;
    var i: usize = num_words;
    while (i > 0) {
        i -= 1;
        const w = mask.__bits[i];
        if (w != 0 or started) {
            var buf: [32]u8 = undefined;
            var pos: usize = 0;
            var j: usize = word_bits / 4;
            while (j > 0) {
                j -= 1;
                const nib = @as(u8, @intCast((w >> @as(u6, @intCast(j * 4))) & 0xf));
                if (nib != 0 or started or j == 0) {
                    buf[pos] = hex_chars[nib];
                    pos += 1;
                    started = true;
                }
            }
            if (i > 0 or started) {
                while (pos < word_bits / 4) {
                    buf[pos] = '0';
                    pos += 1;
                }
            }
            core.writeAll(1, buf[0..pos]);
            started = true;
        }
    }
    if (!started) core.writeAll(1, "0");
}

fn parseMask(s: []const u8) ?core.c.cpu_set_t {
    var mask: core.c.cpu_set_t = undefined;
    @memset(@as([*]u8, @ptrCast(&mask))[0..@sizeOf(core.c.cpu_set_t)], 0);

    var hex = s;
    if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X"))
        hex = hex[2..];
    if (hex.len == 0) return mask;

    const hex_per_word = word_bits / 4;
    var pos = hex.len;
    var word_idx: usize = 0;
    while (pos > 0) {
        const chunk_end = pos;
        const chunk_start = if (pos >= hex_per_word) pos - hex_per_word else 0;
        const chunk = hex[chunk_start..chunk_end];
        const val = std.fmt.parseUnsigned(word_type, chunk, 16) catch return null;
        if (word_idx < num_words) {
            mask.__bits[word_idx] = val;
        }
        word_idx += 1;
        pos = chunk_start;
    }
    return mask;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: taskset [-p] [MASK] [PID | CMD...]\n", .{});

    var i: usize = 1;
    var opt_pid = false;

    if (args.len > 1 and std.mem.eql(u8, args[1], "-p")) {
        opt_pid = true;
        i = 2;
    }

    if (opt_pid) {
        if (i >= args.len) return core.die(1, "taskset: -p requires PID\n", .{});

        if (i + 1 < args.len) {
            const mask_str = args[i];
            const pid = std.fmt.parseInt(c_int, args[i + 1], 10) catch return core.die(1, "taskset: invalid PID\n", .{});
            const new_mask = parseMask(mask_str) orelse return core.die(1, "taskset: invalid mask '{s}'\n", .{mask_str});
            if (core.c.sched_setaffinity(pid, @sizeOf(core.c.cpu_set_t), &new_mask) != 0)
                return core.die(1, "taskset: failed to set affinity\n", .{});
            return 0;
        } else {
            const pid = std.fmt.parseInt(c_int, args[i], 10) catch return core.die(1, "taskset: invalid PID\n", .{});
            var mask: core.c.cpu_set_t = undefined;
            if (core.c.sched_getaffinity(pid, @sizeOf(core.c.cpu_set_t), &mask) != 0)
                return core.die(1, "taskset: failed to get affinity\n", .{});

            var buf: [128]u8 = undefined;
            const pid_line = std.fmt.bufPrint(&buf, "pid {d}'s current affinity mask: ", .{pid}) catch return 1;
            core.writeAll(1, pid_line);
            printMask(&mask);
            core.writeAll(1, "\n");
            return 0;
        }
    }

    if (i >= args.len) return core.die(1, "taskset: MASK required\n", .{});
    const mask_str = args[i];
    const new_mask = parseMask(mask_str) orelse return core.die(1, "taskset: invalid mask '{s}'\n", .{mask_str});

    i += 1;
    if (i >= args.len) return core.die(1, "taskset: no command specified\n", .{});

    const alloc = std.heap.page_allocator;
    const pid = core.c.fork();
    if (pid < 0) return 126;

    if (pid == 0) {
        if (core.c.sched_setaffinity(0, @sizeOf(core.c.cpu_set_t), &new_mask) != 0)
            core.c._exit(1);

        const c_argv = alloc.alloc([*c]u8, args.len - i + 1) catch core.c._exit(126);
        for (args[i..], 0..) |arg, j| {
            c_argv[j] = (alloc.dupeZ(u8, arg) catch core.c._exit(126)).ptr;
        }
        c_argv[args.len - i] = null;
        _ = core.c.execvp(c_argv[0], c_argv.ptr);
        core.c._exit(127);
    }

    var st: c_int = 0;
    _ = core.c.waitpid(pid, &st, 0);
    if (core.c.WIFEXITED(st)) return @intCast(core.c.WEXITSTATUS(st));
    return 1;
}
