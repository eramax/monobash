const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "unzip", .main = main };

fn readLe16(buf: []const u8, off: usize) u16 {
    return @as(u16, buf[off]) | (@as(u16, buf[off + 1]) << 8);
}

fn readLe32(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off]) | (@as(u32, buf[off + 1]) << 8) | (@as(u32, buf[off + 2]) << 16) | (@as(u32, buf[off + 3]) << 24);
}

fn readAllFd(alloc: std.mem.Allocator, fd: c_int) ![]u8 {
    var buf = try alloc.alloc(u8, 65536);
    var pos: usize = 0;
    while (true) {
        if (pos >= buf.len) buf = try alloc.realloc(buf, buf.len * 2);
        const n = core.c.read(fd, buf.ptr + pos, buf.len - pos);
        if (n < 0) return error.ReadError;
        if (n == 0) break;
        pos += @intCast(n);
    }
    return buf[0..pos];
}

fn mkdirAll(path: []const u8) void {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    for (0..path.len) |i| {
        if (buf[i] == '/') {
            buf[i] = 0;
            _ = core.c.mkdir(buf[0..i :0].ptr, 0o755);
            buf[i] = '/';
        }
    }
    _ = core.c.mkdir(buf[0..path.len :0].ptr, 0o755);
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "unzip: usage: unzip [-l] [-d DIR] ARCHIVE.zip\n", .{});

    var i: usize = 1;
    var list_mode = false;
    var extract_dir: ?[]const u8 = null;

    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { i += 1; break; }
        const opt = args[i];
        if (std.mem.eql(u8, opt, "-l")) {
            list_mode = true;
        } else if (std.mem.eql(u8, opt, "-d") and i + 1 < args.len) {
            extract_dir = args[i + 1];
            i += 1;
        } else {
            for (opt[1..]) |c| {
                switch (c) {
                    'l' => list_mode = true,
                    else => return core.die(1, "unzip: unknown option '{c}'\n", .{c}),
                }
            }
        }
        i += 1;
    }

    if (i >= args.len) return core.die(1, "unzip: missing archive\n", .{});
    const archive = args[i];

    var archive_buf: [4096:0]u8 = undefined;
    if (archive.len >= archive_buf.len) return 1;
    @memcpy(archive_buf[0..archive.len], archive);
    archive_buf[archive.len] = 0;

    const fd = core.c.open(archive_buf[0..archive.len :0].ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "unzip: cannot open '{s}'\n", .{archive});
    defer _ = core.c.close(fd);

    const alloc = std.heap.page_allocator;
    const data = readAllFd(alloc, fd) catch return 1;
    defer alloc.free(data);

    if (data.len < 22) return core.die(1, "unzip: empty or corrupt file\n", .{});

    const eocd_sig: u32 = 0x06054b50;
    var eocd_pos: usize = data.len - 22;
    while (eocd_pos > 0) {
        if (readLe32(data, eocd_pos) == eocd_sig) break;
        eocd_pos -|= 1;
    }
    if (readLe32(data, eocd_pos) != eocd_sig) return core.die(1, "unzip: end of central directory not found\n", .{});

    const cd_offset = readLe32(data, eocd_pos + 16);
    const cd_entries = readLe16(data, eocd_pos + 10);

    var pos: usize = @as(usize, @intCast(cd_offset));
    var entry_count: usize = 0;

    const dir_prefix = extract_dir orelse "";

    while (entry_count < cd_entries) {
        if (pos + 46 > data.len) break;
        if (readLe32(data, pos) != 0x02014b50) break;

        const comp_method = readLe16(data, pos + 10);
        const comp_size = readLe32(data, pos + 20);
        const name_len = readLe16(data, pos + 28);
        const extra_len = readLe16(data, pos + 30);
        const comment_len = readLe16(data, pos + 32);
        const local_offset = readLe32(data, pos + 42);

        if (pos + 46 + name_len > data.len) break;
        const name = data[pos + 46 .. pos + 46 + name_len];

        if (comp_method != 0) {
            if (list_mode) {
                core.eprint("unzip: unsupported compression method {d} for '{s}'\n", .{ comp_method, name });
            } else {
                core.eprint("unzip: unsupported compression method {d} for '{s}'\n", .{ comp_method, name });
            }
        }

        if (list_mode) {
            var line: [4096]u8 = undefined;
            const s = std.fmt.bufPrint(&line, "  {s}\n", .{name}) catch {
                core.writeAll(1, name);
                core.writeAll(1, "\n");
                continue;
            };
            core.writeAll(1, s);
        } else {
            const local_pos = @as(usize, @intCast(local_offset));
            if (local_pos + 30 + name_len + extra_len > data.len) {
                entry_count += 1;
                pos += 46 + name_len + extra_len + comment_len;
                continue;
            }
            const local_name_len = readLe16(data, local_pos + 26);
            const local_extra_len = readLe16(data, local_pos + 28);
            const file_data_start = local_pos + 30 + local_name_len + local_extra_len;
            const file_data_end = file_data_start + @as(usize, @intCast(comp_size));

            if (file_data_end > data.len) {
                entry_count += 1;
                pos += 46 + name_len + extra_len + comment_len;
                continue;
            }
            const file_data = data[file_data_start..file_data_end];

            var out_path_buf: [4096:0]u8 = undefined;
            var out_path: []const u8 = name;
            if (dir_prefix.len > 0) {
                const full = std.fmt.bufPrint(&out_path_buf, "{s}/{s}", .{ dir_prefix, name }) catch {
                    entry_count += 1;
                    pos += 46 + name_len + extra_len + comment_len;
                    continue;
                };
                out_path = full;
            }

            var out_z: [4096:0]u8 = undefined;
            if (out_path.len >= out_z.len) {
                entry_count += 1;
                pos += 46 + name_len + extra_len + comment_len;
                continue;
            }
            @memcpy(out_z[0..out_path.len], out_path);
            out_z[out_path.len] = 0;

            // Check if it's a directory
            if (name.len > 0 and name[name.len - 1] == '/') {
                mkdirAll(out_path);
            } else {
                mkdirAll(std.fs.path.dirname(out_path) orelse ".");
                const ofd = core.c.open(out_z[0..out_path.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_TRUNC, @as(c_uint, 0o644));
                if (ofd >= 0) {
                    var woff: usize = 0;
                    while (woff < file_data.len) {
                        const w = core.c.write(ofd, file_data.ptr + woff, file_data.len - woff);
                        if (w < 0) break;
                        woff += @intCast(w);
                    }
                    _ = core.c.close(ofd);
                }
            }
        }

        entry_count += 1;
        pos += 46 + name_len + extra_len + comment_len;
    }

    return 0;
}
