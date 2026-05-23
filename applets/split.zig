const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "split", .main = main };

fn nextName(name: []u8, pos: usize) bool {
    var p = pos;
    while (p > 0) {
        p -= 1;
        if (name[p] < 'z') {
            name[p] += 1;
            return true;
        }
        name[p] = 'a';
    }
    return false;
}

pub fn main(args: [][]const u8) u8 {
    var lines: ?usize = null;
    var bytes: ?usize = null;
    var i: usize = 1;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const arg = args[i];
        if (arg.len > 2 and arg[1] == 'l') {
            lines = std.fmt.parseUnsigned(usize, arg[2..], 10) catch
                return core.die(1, "split: invalid number: {s}\n", .{arg});
            i += 1;
            continue;
        }
        if (arg.len > 2 and arg[1] == 'b') {
            bytes = std.fmt.parseUnsigned(usize, arg[2..], 10) catch
                return core.die(1, "split: invalid number: {s}\n", .{arg});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-l")) {
            i += 1;
            if (i >= args.len) return core.die(1, "split: option requires an argument: -l\n", .{});
            lines = std.fmt.parseUnsigned(usize, args[i], 10) catch
                return core.die(1, "split: invalid number: {s}\n", .{args[i]});
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-b")) {
            i += 1;
            if (i >= args.len) return core.die(1, "split: option requires an argument: -b\n", .{});
            bytes = std.fmt.parseUnsigned(usize, args[i], 10) catch
                return core.die(1, "split: invalid number: {s}\n", .{args[i]});
            i += 1;
            continue;
        }
        for (arg[1..]) |flag| {
            switch (flag) {
                'l' => {},
                'b' => {},
                else => return core.die(1, "split: unknown flag '-{c}'\n", .{flag}),
            }
        }
        i += 1;
    }

    if (lines == null and bytes == null) {
        lines = 1000;
    }

    var fname_buf: [32]u8 = undefined;
    fname_buf[0..3].* = "xaa".*;
    var name_pos: usize = 3;

    const alloc = std.heap.page_allocator;

    if (i >= args.len) {
        return core.die(1, "split: missing file\n", .{});
    }
    const f = args[i];
    var fbuf: [4096:0]u8 = undefined;
    if (f.len >= fbuf.len) return core.die(1, "split: path too long\n", .{});
    @memcpy(fbuf[0..f.len], f);
    fbuf[f.len] = 0;
    const fd = core.c.open(&fbuf, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "split: {s}: No such file or directory\n", .{f});
    defer _ = core.c.close(fd);

    if (bytes) |bcount| {
        const data = core.readAll(alloc, fd, 1024 * 1024) catch return 1;
        defer alloc.free(data);
        var offset: usize = 0;
        while (offset < data.len) {
            const chunk = data[offset..@min(offset + bcount, data.len)];
            const oname = fname_buf[0..name_pos];
            var ofbuf: [4096:0]u8 = undefined;
            @memcpy(ofbuf[0..oname.len], oname);
            ofbuf[oname.len] = 0;
            const ofd = core.c.open(&ofbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
            if (ofd < 0) {
                core.eprint("split: cannot create {s}\n", .{oname});
                return 1;
            }
            core.writeAll(ofd, chunk);
            _ = core.c.close(ofd);
            offset += chunk.len;
            if (!nextName(&fname_buf, name_pos)) {
                fname_buf[name_pos] = 'a';
                name_pos += 1;
                fname_buf[name_pos] = 'a';
            }
        }
    } else if (lines) |lcount| {
        var reader = core.LineReader.init(fd);
        var out_lines: std.ArrayListAligned(u8, null) = .empty;
        defer out_lines.deinit(alloc);
        var line_count: usize = 0;

        while (reader.next()) |line| {
            out_lines.appendSlice(alloc, line) catch return 1;
            out_lines.append(alloc, '\n') catch return 1;
            line_count += 1;

            if (line_count >= lcount) {
                flushOutput(&out_lines, &fname_buf, &name_pos) catch return 1;
                line_count = 0;
            }
        }
        if (out_lines.items.len > 0) {
            flushOutput(&out_lines, &fname_buf, &name_pos) catch return 1;
        }
    }

    return 0;
}

fn flushOutput(out_lines: *std.ArrayListAligned(u8, null), fname_buf: []u8, name_pos: *usize) !void {
    const oname = fname_buf[0..name_pos.*];
    var ofbuf: [4096:0]u8 = undefined;
    @memcpy(ofbuf[0..oname.len], oname);
    ofbuf[oname.len] = 0;
    const ofd = core.c.open(&ofbuf, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
    if (ofd < 0) {
        core.eprint("split: cannot create {s}\n", .{oname});
        return error.FileOpenFailed;
    }
    core.writeAll(ofd, out_lines.items);
    _ = core.c.close(ofd);
    out_lines.clearRetainingCapacity();
    if (!nextName(fname_buf, name_pos.*)) {
        fname_buf[name_pos.*] = 'a';
        name_pos.* += 1;
        fname_buf[name_pos.*] = 'a';
    }
}
