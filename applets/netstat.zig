const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "netstat", .main = main };

const State = enum(u8) {
    established = 0x01,
    syn_sent = 0x02,
    syn_recv = 0x03,
    fin_wait1 = 0x04,
    fin_wait2 = 0x05,
    time_wait = 0x06,
    close = 0x07,
    close_wait = 0x08,
    last_ack = 0x09,
    listen = 0x0A,
    closing = 0x0B,
    _,
};

fn stateName(s: u8) []const u8 {
    return switch (s) {
        0x01 => "ESTABLISHED",
        0x02 => "SYN_SENT",
        0x03 => "SYN_RECV",
        0x04 => "FIN_WAIT1",
        0x05 => "FIN_WAIT2",
        0x06 => "TIME_WAIT",
        0x07 => "CLOSE",
        0x08 => "CLOSE_WAIT",
        0x09 => "LAST_ACK",
        0x0A => "LISTEN",
        0x0B => "CLOSING",
        else => "UNKNOWN",
    };
}

fn protoName(proto: []const u8) []const u8 {
    if (std.mem.eql(u8, proto, "tcp")) return "tcp";
    if (std.mem.eql(u8, proto, "udp")) return "udp";
    if (std.mem.eql(u8, proto, "raw")) return "raw";
    return proto;
}

fn findProcByInode(inode: u64, alloc: std.mem.Allocator) ?[]u8 {
    const dir_fd = core.c.opendir("/proc".ptr);
    if (dir_fd == null) return null;
    defer _ = core.c.closedir(dir_fd);

    while (true) {
        const dent = core.c.readdir(dir_fd) orelse break;
        const name = std.mem.sliceTo(@as([*]u8, @ptrCast(&dent.*.d_name)), 0);
        _ = std.fmt.parseInt(u64, name, 10) catch continue;

        const fd_path = std.fmt.allocPrint(alloc, "/proc/{s}/fd\x00", .{name}) catch continue;
        defer alloc.free(fd_path);

        const fd_dir = core.c.opendir(@as([*]u8, @ptrCast(fd_path.ptr)));
        if (fd_dir == null) continue;
        defer _ = core.c.closedir(fd_dir);

        while (true) {
            const fdent = core.c.readdir(fd_dir) orelse break;
            const fname = std.mem.sliceTo(@as([*]u8, @ptrCast(&fdent.*.d_name)), 0);
            if (fname.len == 0 or fname[0] == '.') continue;

            const link_path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ fd_path, fname }) catch continue;
            defer alloc.free(link_path);

            var link_buf: [256]u8 = undefined;
            const llen = core.c.readlink(@as([*]u8, @ptrCast(link_path.ptr)), &link_buf, link_buf.len);
            if (llen < 0) continue;
            const link = link_buf[0..@as(usize, @intCast(llen))];

            const prefix = "socket:[";
            if (!std.mem.startsWith(u8, link, prefix)) continue;
            const close_b = std.mem.indexOfScalar(u8, link, ']') orelse continue;
            const sock_inode = std.fmt.parseInt(u64, link[prefix.len..close_b], 10) catch continue;
            if (sock_inode != inode) continue;

            const comm_path = std.fmt.allocPrint(alloc, "/proc/{s}/comm", .{name}) catch continue;
            defer alloc.free(comm_path);
            const comm = readLine(alloc, comm_path);
            if (comm) |c| return c;
            return alloc.dupe(u8, name) catch null;
        }
    }
    return null;
}

fn readLine(alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    var p: [4096:0]u8 = undefined;
    if (path.len >= p.len) return null;
    @memcpy(p[0..path.len], path);
    p[path.len] = 0;
    const fd = core.c.open(&p, core.c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 4096) catch return null;
    defer alloc.free(data);
    var i: usize = 0;
    while (i < data.len and data[i] != '\n' and data[i] != '\r') i += 1;
    while (i > 0 and (data[i - 1] == ' ' or data[i - 1] == '\t')) i -= 1;
    return alloc.dupe(u8, data[0..i]) catch null;
}

fn parseHexIp(hex: []const u8) [4]u8 {
    if (hex.len < 8) return .{ 0, 0, 0, 0 };
    const val = std.fmt.parseInt(u32, hex[0..8], 16) catch return .{ 0, 0, 0, 0 };
    return @as([4]u8, @bitCast(val));
}

fn parseProcNet(alloc: std.mem.Allocator, path: []const u8, proto: []const u8, show_listen: bool, show_tcp: bool, show_udp: bool, _: bool, show_prog: bool) void {
    const is_tcp = std.mem.eql(u8, proto, "tcp");
    const is_udp = std.mem.eql(u8, proto, "udp");
    if (!((is_tcp and show_tcp) or (is_udp and show_udp) or (!is_tcp and !is_udp))) return;

    var p: [4096:0]u8 = undefined;
    if (path.len >= p.len) return;
    @memcpy(p[0..path.len], path);
    p[path.len] = 0;
    const fd = core.c.open(&p, core.c.O_RDONLY);
    if (fd < 0) return;
    defer _ = core.c.close(fd);
    const data = core.readAll(alloc, fd, 65536) catch return;
    defer alloc.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ' ');
        var field_idx: usize = 0;
        var local_addr: []const u8 = "";
        var rem_addr: []const u8 = "";
        var st: u8 = 0;
        var inode: u64 = 0;
        var txq: u64 = 0;
        var rxq: u64 = 0;
        while (fields.next()) |f| {
            if (f.len == 0) continue;
            switch (field_idx) {
                1 => {
                    if (std.mem.indexOfScalar(u8, f, ':') == null) break;
                    local_addr = f;
                },
                2 => rem_addr = f,
                3 => st = std.fmt.parseInt(u8, f, 16) catch 0,
                4 => {
                    const colon = std.mem.indexOfScalar(u8, f, ':') orelse break;
                    txq = std.fmt.parseInt(u64, f[0..colon], 16) catch 0;
                    rxq = std.fmt.parseInt(u64, f[colon + 1 ..], 16) catch 0;
                },
                9 => inode = std.fmt.parseInt(u64, f, 10) catch 0,
                else => {},
            }
            field_idx += 1;
        }

        if (show_listen and st != 0x0A) continue;
        if (!show_listen and !show_tcp and !show_udp and st == 0x0A) continue;

        if (local_addr.len == 0 or rem_addr.len == 0) continue;
        const loc_colon = std.mem.indexOfScalar(u8, local_addr, ':') orelse continue;
        const rem_colon = std.mem.indexOfScalar(u8, rem_addr, ':') orelse continue;
        const loc_ip_str = local_addr[0..loc_colon];
        const loc_port_str = local_addr[loc_colon + 1 ..];
        const rem_ip_str = rem_addr[0..rem_colon];
        const rem_port_str = rem_addr[rem_colon + 1 ..];

        const loc_octets = parseHexIp(loc_ip_str);
        const rem_octets = parseHexIp(rem_ip_str);
        const loc_port = std.fmt.parseInt(u16, loc_port_str, 16) catch 0;
        const rem_port = std.fmt.parseInt(u16, rem_port_str, 16) catch 0;

        var proc: []const u8 = "";
        var proc_buf: [64]u8 = undefined;
        if (show_prog and inode > 0) {
            if (findProcByInode(inode, alloc)) |pname| {
                defer alloc.free(pname);
                proc = pname;
            }
        }
        if (proc.len > 0) {
            const ps = std.fmt.bufPrint(&proc_buf, "{s}/{d}", .{ proc, @as(u32, @intCast(inode)) }) catch "";
            proc = ps;
        }

        var out: [256]u8 = undefined;
        const o = std.fmt.bufPrint(&out, "{s}  {d}.{d}.{d}.{d}:{d} {d}.{d}.{d}.{d}:{d} {s} {d}/{d} {s}\n",
            .{ protoName(proto),
               loc_octets[0], loc_octets[1], loc_octets[2], loc_octets[3], loc_port,
               rem_octets[0], rem_octets[1], rem_octets[2], rem_octets[3], rem_port,
               stateName(st), txq, rxq, proc },
        ) catch continue;
        core.writeAll(1, o);
    }
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var show_tcp = false;
    var show_udp = false;
    var show_listen = false;
    var numeric = false;
    var show_prog = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-t")) show_tcp = true;
        if (std.mem.eql(u8, arg, "-u")) show_udp = true;
        if (std.mem.eql(u8, arg, "-l")) show_listen = true;
        if (std.mem.eql(u8, arg, "-n")) numeric = true;
        if (std.mem.eql(u8, arg, "-p")) show_prog = true;
    }
    if (!show_tcp and !show_udp) {
        show_tcp = true;
        show_udp = true;
    }

    parseProcNet(alloc, "/proc/net/tcp", "tcp", show_listen, show_tcp, show_udp, numeric, show_prog);
    parseProcNet(alloc, "/proc/net/udp", "udp", show_listen, show_tcp, show_udp, numeric, show_prog);
    parseProcNet(alloc, "/proc/net/raw", "raw", show_listen, false, false, numeric, show_prog);
    return 0;
}
