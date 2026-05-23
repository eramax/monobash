const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "top", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const stat_fd = core.c.open("/proc/stat", core.c.O_RDONLY);
    if (stat_fd < 0) return 1;
    defer _ = core.c.close(stat_fd);
    const stat_data = core.readAll(alloc, stat_fd, 4096) catch return 1;
    defer alloc.free(stat_data);

    var cpu_user: u64 = 0;
    var cpu_nice: u64 = 0;
    var cpu_sys: u64 = 0;
    var cpu_idle: u64 = 0;
    if (std.mem.startsWith(u8, stat_data, "cpu ")) {
        const nl = std.mem.indexOfScalar(u8, stat_data, '\n') orelse stat_data.len;
        const first_line = stat_data[0..nl];
        var fields = std.mem.splitScalar(u8, first_line, ' ');
        _ = fields.next();
        cpu_user = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
        cpu_nice = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
        cpu_sys = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
        cpu_idle = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
    }
    const cpu_total = cpu_user + cpu_nice + cpu_sys + cpu_idle;
    const cpu_pct = if (cpu_total > 0) @divTrunc(cpu_sys * 100, cpu_total) else 0;

    const mem_fd = core.c.open("/proc/meminfo", core.c.O_RDONLY);
    if (mem_fd < 0) return 1;
    defer _ = core.c.close(mem_fd);
    const mem_data = core.readAll(alloc, mem_fd, 4096) catch return 1;
    defer alloc.free(mem_data);

    var mem_total: u64 = 0;
    var mem_free: u64 = 0;
    var mem_avail: u64 = 0;
    var lines = std.mem.splitScalar(u8, mem_data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            mem_total = std.fmt.parseInt(u64, std.mem.trim(u8, line["MemTotal:".len..], " \t"), 10) catch 0;
        } else if (std.mem.startsWith(u8, line, "MemFree:")) {
            mem_free = std.fmt.parseInt(u64, std.mem.trim(u8, line["MemFree:".len..], " \t"), 10) catch 0;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            mem_avail = std.fmt.parseInt(u64, std.mem.trim(u8, line["MemAvailable:".len..], " \t"), 10) catch 0;
        }
    }

    var hdr_buf: [512]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf,
        "top - {d:>3}% cpu  Mem: {d:>6} MB total, {d:>6} MB free, {d:>6} MB avail\n\n  PID CMD                         STAT\n",
        .{ cpu_pct, mem_total / 1024, mem_free / 1024, mem_avail / 1024 },
    ) catch "";
    core.writeAll(1, hdr);

    const d = core.c.opendir("/proc") orelse return 1;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent_ptr: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent_ptr.d_name)), 0);

        const pid = std.fmt.parseInt(usize, name, 10) catch continue;

        var path_buf: [64]u8 = undefined;
        const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch continue;
        var z_buf: [256:0]u8 = undefined;
        if (stat_path.len >= z_buf.len) continue;
        @memcpy(z_buf[0..stat_path.len], stat_path);
        z_buf[stat_path.len] = 0;

        const fd = core.c.open(z_buf[0..stat_path.len :0].ptr, core.c.O_RDONLY);
        if (fd < 0) continue;
        defer _ = core.c.close(fd);

        const data = core.readAll(alloc, fd, 4096) catch continue;
        defer alloc.free(data);

        const open_paren = std.mem.indexOfScalar(u8, data, '(') orelse continue;
        const close_paren = std.mem.lastIndexOfScalar(u8, data, ')') orelse continue;
        const comm = data[open_paren + 1 .. close_paren];
        const rest = data[close_paren + 2 ..];
        const state = if (rest.len > 0) rest[0..1] else "?";

        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{d:>5} {s:<28} {s}\n", .{ pid, comm, state }) catch continue;
        core.writeAll(1, line);
    }

    return 0;
}
