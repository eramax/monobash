const std = @import("std");
const core = @import("core.zig");
const mvzr = @import("mvzr");

pub const meta = core.AppletMeta{ .name = "sed", .main = main };

pub fn main(args: [][]const u8) u8 {
    var quiet = false;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| {
            switch (flag) {
                'n' => quiet = true,
                'E' => {},
                else => return core.die(1, "sed: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "sed: missing script\n", .{});
    const script = args[i];
    i += 1;
    const files = args[i..];

    // Parse s/pattern/replacement/flags
    if (script.len < 3 or script[0] != 's' or script.len < 4) {
        return core.die(1, "sed: only s/// command supported\n", .{});
    }
    const sep = script[1];
    const sep_end = std.mem.lastIndexOfScalar(u8, script, sep) orelse
        return core.die(1, "sed: unterminated s/// command\n", .{});
    if (sep_end <= 2) return core.die(1, "sed: invalid s/// command\n", .{});

    const pattern = script[2..sep_end];
    // Find separator for replacement: from sep_end forward, look for next sep or end
    const rest = script[sep_end + 1 ..];
    const repl_end = std.mem.indexOfScalar(u8, rest, sep) orelse rest.len;
    const replacement = rest[0..repl_end];
    const flags = rest[repl_end..];

    const is_global = std.mem.indexOfScalar(u8, flags, 'g') != null;

    const re = mvzr.Regex.compile(pattern) orelse
        return core.die(1, "sed: invalid regex pattern\n", .{});

    var exit_code: u8 = 0;

    if (files.len == 0) {
        processStdin(&re, replacement, is_global, quiet);
    } else for (files) |f| {
        var fbuf: [4096:0]u8 = undefined;
        if (f.len >= fbuf.len) {
            core.eprint("sed: {s}: path too long\n", .{f});
            exit_code = 1;
            continue;
        }
        @memcpy(fbuf[0..f.len], f);
        fbuf[f.len] = 0;
        const fd = core.c.open(&fbuf, core.c.O_RDONLY);
        if (fd < 0) {
            core.eprint("sed: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        }
        defer _ = core.c.close(fd);
        processFd(fd, &re, replacement, is_global, quiet);
    }

    return exit_code;
}

fn processStdin(re: *const mvzr.Regex, repl: []const u8, global: bool, quiet: bool) void {
    processFd(0, re, repl, global, quiet);
}

fn processFd(fd: c_int, re: *const mvzr.Regex, repl: []const u8, global: bool, quiet: bool) void {
    const alloc = std.heap.page_allocator;
    const data = core.readAll(alloc, fd, 1024 * 1024) catch return;
    defer alloc.free(data);

    var start: usize = 0;
    var out: [65536]u8 = undefined;

    while (start < data.len) {
        const end = if (std.mem.indexOfScalar(u8, data[start..], '\n')) |nl| start + nl else data.len;
        const line = data[start..end];
        const modified = substituteLine(line, re, repl, global, &out);
        if (modified) |new_line| {
            if (!quiet) {
                core.writeAll(1, new_line);
                core.writeAll(1, "\n");
            }
        } else {
            if (!quiet) {
                const n = @min(line.len, out.len - 1);
                @memcpy(out[0..n], line[0..n]);
                out[n] = '\n';
                core.writeAll(1, out[0 .. n + 1]);
            }
        }
        start = end + 1;
    }
}

fn substituteLine(line: []const u8, re: *const mvzr.Regex, repl: []const u8, global: bool, buf: []u8) ?[]const u8 {
    var pos: usize = 0;
    var prev_end: usize = 0;
    var found = false;

    if (global) {
        var iter = re.iterator(line);
        while (iter.next()) |match| {
            found = true;
            // Copy text before match
            const before = line[prev_end..match.start];
            if (pos + before.len + repl.len > buf.len) return null;
            @memcpy(buf[pos..][0..before.len], before);
            pos += before.len;
            @memcpy(buf[pos..][0..repl.len], repl);
            pos += repl.len;
            prev_end = match.end;
        }
        if (found) {
            const after = line[prev_end..];
            if (pos + after.len > buf.len) return null;
            @memcpy(buf[pos..][0..after.len], after);
            pos += after.len;
        }
    } else {
        if (re.match(line)) |match| {
            found = true;
            const before = line[0..match.start];
            const after = line[match.end..];
            const total = before.len + repl.len + after.len;
            if (total > buf.len) return null;
            @memcpy(buf[0..before.len], before);
            pos = before.len;
            @memcpy(buf[pos..][0..repl.len], repl);
            pos += repl.len;
            @memcpy(buf[pos..][0..after.len], after);
            pos += after.len;
        }
    }

    return if (found) buf[0..pos] else null;
}
