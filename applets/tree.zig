const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "tree", .main = main };
const DirEntry = struct { name: []u8, is_dir: bool };
pub fn main(args: [][]const u8) u8 {
    var max_depth: usize = std.math.maxInt(usize);
    var all = false;
    var dirs_only = false;
    var root: []const u8 = ".";
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-L")) {
                i += 1;
                if (i >= args.len) return core.die(1, "tree: missing depth after -L\n", .{});
                max_depth = std.fmt.parseInt(usize, args[i], 10) catch return core.die(1, "tree: invalid depth\n", .{});
            } else if (std.mem.eql(u8, arg, "-a")) {
                all = true;
            } else if (std.mem.eql(u8, arg, "-d")) {
                dirs_only = true;
            } else if (std.mem.eql(u8, arg, "--")) {
                i += 1; if (i < args.len) root = args[i]; break;
            } else return core.die(1, "tree: unknown flag '{s}'\n", .{arg});
        } else root = arg;
        i += 1;
    }
    core.writeAll(1, root);
    core.writeAll(1, "\n");
    printTree(root, "", 0, max_depth, all, dirs_only);
    return 0;
}
fn printTree(path: []const u8, prefix: []const u8, depth: usize, max_depth: usize, all: bool, dirs_only: bool) void {
    if (depth > max_depth) return;
    var pbuf: [4096:0]u8 = undefined;
    if (path.len >= pbuf.len) return;
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    const dir = core.c.opendir(&pbuf) orelse return;
    defer _ = core.c.closedir(dir);
    const alloc = std.heap.page_allocator;
    var entries = std.ArrayListAligned(DirEntry, null).empty;
    defer {
        for (entries.items) |e| alloc.free(e.name);
        entries.deinit(alloc);
    }
    while (true) {
        const entry = core.c.readdir(dir) orelse break;
        const de = @as(*core.c.struct_dirent, @ptrCast(@alignCast(entry)));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&de.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!all and name.len > 0 and name[0] == '.') continue;
        var fbuf: [4096:0]u8 = undefined;
        if (path.len > 0 and path[path.len - 1] == '/') {
            _ = std.fmt.bufPrint(&fbuf, "{s}{s}", .{ path, name }) catch continue;
        } else {
            _ = std.fmt.bufPrint(&fbuf, "{s}/{s}", .{ path, name }) catch continue;
        }
        var st: core.c.struct_stat = undefined;
        const is_dir = if (core.c.stat(&fbuf, &st) == 0) (st.st_mode & core.c.S_IFMT) == core.c.S_IFDIR else false;
        if (dirs_only and !is_dir) continue;
        const dup = alloc.dupe(u8, name) catch continue;
        entries.append(alloc, .{ .name = dup, .is_dir = is_dir }) catch { alloc.free(dup); continue; };
    }
    std.sort.block(DirEntry, entries.items, {}, struct {
        fn less(_: void, a: DirEntry, b: DirEntry) bool {
            if (a.is_dir and !b.is_dir) return true;
            if (!a.is_dir and b.is_dir) return false;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.less);
    for (entries.items, 0..) |entry, idx| {
        const last = idx == entries.items.len - 1;
        const conn = if (last) "└── " else "├── ";
        core.writeAll(1, prefix);
        core.writeAll(1, conn);
        core.writeAll(1, entry.name);
        core.writeAll(1, "\n");
        if (entry.is_dir) {
            var sub_pre: [4096]u8 = undefined;
            const sp = std.fmt.bufPrint(&sub_pre, "{s}{s}", .{ prefix, if (last) "    " else "│   " }) catch "";
            var fbuf2: [4096:0]u8 = undefined;
            const full2 = if (path.len > 0 and path[path.len - 1] == '/')
                std.fmt.bufPrint(&fbuf2, "{s}{s}", .{ path, entry.name }) catch continue
            else
                std.fmt.bufPrint(&fbuf2, "{s}/{s}", .{ path, entry.name }) catch continue;
            printTree(full2, sp, depth + 1, max_depth, all, dirs_only);
        }
    }
}
