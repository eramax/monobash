const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "realpath", .main = main };

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "usage: realpath FILE...\n", .{});
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) { i += 1; break; }
        for (arg[1..]) |c| {
            switch (c) {
                'q', 's', 'm', 'e' => {},
                else => return core.die(1, "realpath: invalid option -- '{c}'\n", .{c}),
            }
        }
        i += 1;
    }
    var rc: u8 = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        var zpath: [4096:0]u8 = undefined;
        if (arg.len >= zpath.len) { rc = 1; continue; }
        @memcpy(zpath[0..arg.len], arg);
        zpath[arg.len] = 0;

        var out: [4096]u8 = undefined;
        const res = resolve(&zpath, &out);
        if (res) |r| {
            core.writeAll(1, r);
            core.writeAll(1, "\n");
        } else {
            core.eprint("realpath: {s}: No such file or directory\n", .{arg});
            rc = 1;
        }
    }
    return rc;
}

fn resolve(path: [:0]u8, out: []u8) ?[]u8 {
    while (true) {
        var real_buf: [4096]u8 = undefined;
        const rp = core.c.realpath(path, &real_buf);
        if (rp) |_| {
            const len = std.mem.indexOfScalar(u8, @as([*c]u8, @ptrCast(&real_buf))[0..4096], 0) orelse 4096;
            if (len <= out.len) {
                @memcpy(out[0..len], real_buf[0..len]);
                return out[0..len];
            }
            return null;
        }

        var linkbuf: [4096]u8 = undefined;
        const linklen = core.c.readlink(path, &linkbuf, linkbuf.len);
        if (linklen > 0) {
            const target = linkbuf[0..@intCast(linklen)];
            var abs_buf: [4096]u8 = undefined;
            const abs_target = if (target.len > 0 and target[0] == '/')
                target
            else
                joinWithCwd(target, &abs_buf) orelse return null;
            if (abs_target.len >= 4096) return null;
            var new_path: [4096:0]u8 = undefined;
            @memcpy(new_path[0..abs_target.len], abs_target);
            new_path[abs_target.len] = 0;
            // Recurse - path and out are distinct
            const res = resolve(&new_path, out);
            if (res) |r| return r;
            return null;
        }

        // Not symlink - resolve parent
        const len = std.mem.indexOfScalar(u8, @as([*c]u8, @ptrCast(path))[0..4096], 0) orelse 4096;
        var start: usize = 0;
        while (start < len and start + 1 < len and path[start] == '/' and path[start + 1] == '/') {
            start += 1;
        }
        var end: usize = len;
        while (end > start + 1 and path[end - 1] == '/') {
            end -= 1;
        }
        const cleaned = path[start..end];
        if (cleaned.len == 0) {
            if (out.len >= 1) { out[0] = '/'; return out[0..1]; }
            return null;
        }

        const last_slash = std.mem.lastIndexOfScalar(u8, cleaned, '/');
        if (last_slash) |ls| {
            if (ls == 0) {
                if (cleaned.len <= out.len) {
                    @memcpy(out[0..cleaned.len], cleaned);
                    return out[0..cleaned.len];
                }
                return null;
            }
            const parent = cleaned[0..ls];
            var parent_z: [4096:0]u8 = undefined;
            if (parent.len >= parent_z.len) return null;
            @memcpy(parent_z[0..parent.len], parent);
            parent_z[parent.len] = 0;
            var parent_real: [4096]u8 = undefined;
            const pr = core.c.realpath(&parent_z, &parent_real);
            if (pr == null) return null;
            const plen = std.mem.indexOfScalar(u8, @as([*c]u8, @ptrCast(pr))[0..4096], 0) orelse 4096;
            const pres = pr[0..plen];
            const child = cleaned[ls + 1 ..];
            const total = pres.len + 1 + child.len;
            if (total > out.len) return null;
            @memcpy(out[0..pres.len], pres);
            out[pres.len] = '/';
            @memcpy(out[pres.len + 1 ..], child);
            return out[0..total];
        } else {
            return joinWithCwd(cleaned, out);
        }
    }
}

fn getCwdBuf(buf: []u8) ?[]u8 {
    const ptr = core.c.getcwd(buf.ptr, buf.len);
    if (ptr) |p| {
        return std.mem.sliceTo(@as([*c]u8, @ptrCast(p)), 0);
    }
    return null;
}

fn joinWithCwd(rel: []const u8, out: []u8) ?[]u8 {
    var cwdbuf: [4096]u8 = undefined;
    const cwd = getCwdBuf(&cwdbuf) orelse return null;
    const total = cwd.len + 1 + rel.len;
    if (total > out.len) return null;
    @memcpy(out[0..cwd.len], cwd);
    out[cwd.len] = '/';
    @memcpy(out[cwd.len + 1 ..], rel);
    return out[0..total];
}
