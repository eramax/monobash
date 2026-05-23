const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sed", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(2, "sed: missing script\n", .{});
    var i: usize = 1;
    var quiet = false;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        for (args[i][1..]) |flag| switch (flag) {
            'n' => quiet = true,
            else => return core.die(2, "sed: unknown flag '-{c}'\n", .{flag}),
        };
        i += 1;
    }
    if (i >= args.len) return core.die(2, "sed: missing script\n", .{});
    const script = args[i];
    i += 1;
    const files = args[i..];

    if (script.len < 3 or script[0] != 's' or script[1] != '/')
        return core.die(2, "sed: only s/// command supported\n", .{});
    const delim = script[2];
    const pat_end = std.mem.indexOfScalarPos(u8, script, 3, delim) orelse
        return core.die(2, "sed: invalid s/// command\n", .{});
    const pattern = script[3..pat_end];
    const repl_end = std.mem.indexOfScalarPos(u8, script, pat_end + 1, delim) orelse script.len - 1;
    const replacement = script[pat_end + 1 .. repl_end];
    const flags = if (repl_end + 1 < script.len) script[repl_end + 1 ..] else "";
    const global = std.mem.indexOfScalar(u8, flags, 'g') != null;

    var pat_buf: [4096:0]u8 = undefined;
    if (pattern.len >= pat_buf.len) return core.die(2, "sed: pattern too long\n", .{});
    @memcpy(pat_buf[0..pattern.len], pattern);
    pat_buf[pattern.len] = 0;

    var reg_buf: [1024]u8 align(@alignOf(c_int)) = undefined;
    const regex: *core.c.regex_t = @ptrCast(&reg_buf);
    if (core.c.regcomp(regex, &pat_buf, core.c.REG_EXTENDED) != 0)
        return core.die(2, "sed: invalid regex\n", .{});
    defer core.c.regfree(regex);

    var exit_code: u8 = 0;
    if (files.len == 0) {
        processFd(0, regex, replacement, global, quiet);
    } else for (files) |f| {
        const fd = core.openReadName(f) orelse {
            core.eprint("sed: {s}: No such file or directory\n", .{f});
            exit_code = 1;
            continue;
        };
        processFd(fd, regex, replacement, global, quiet);
        _ = core.c.close(fd);
    }
    return exit_code;
}

fn processFd(fd: c_int, regex: *core.c.regex_t, repl: []const u8, _: bool, quiet: bool) void {
    const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch return;
    defer std.heap.page_allocator.free(data);
    var start: usize = 0;
    var out: [65536]u8 = undefined;

    while (start < data.len) {
        const end = if (std.mem.indexOfScalar(u8, data[start..], '\n')) |nl| start + nl else data.len;
        const line = data[start..end];
        var modified: ?[]const u8 = null;
        var pmatch: [1]core.c.regmatch_t = undefined;
        {
            var zline: [65537:0]u8 = undefined;
            const n = @min(line.len, zline.len - 1);
            @memcpy(zline[0..n], line[0..n]);
            zline[n] = 0;
            if (core.c.regexec(regex, &zline, 1, &pmatch, 0) == 0 and pmatch[0].rm_so >= 0) {
                const so: usize = @intCast(pmatch[0].rm_so);
                const eo: usize = @intCast(pmatch[0].rm_eo);
                const before = line[0..so];
                const after = line[eo..];
                const total = before.len + repl.len + after.len;
                if (total <= out.len) {
                    @memcpy(out[0..before.len], before);
                    @memcpy(out[before.len..][0..repl.len], repl);
                    @memcpy(out[before.len + repl.len ..][0..after.len], after);
                    modified = out[0..total];
                }
            }
        }
        if (modified) |ml| {
            if (!quiet) { core.writeAll(1, ml); core.writeAll(1, "\n"); }
        } else if (!quiet) {
            const n = @min(line.len, out.len - 1);
            @memcpy(out[0..n], line[0..n]);
            out[n] = '\n';
            core.writeAll(1, out[0..n+1]);
        }
        start = end + 1;
    }
}
