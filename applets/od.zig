const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "od", .main = main };
pub fn main(args: [][]const u8) u8 {
    var addr_radix: u8 = 'o';
    var data_type: u8 = 'o';
    var i: usize = 1;
    while (i < args.len and args[i].len > 0 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-A")) {
            i += 1;
            if (i >= args.len) return core.die(1, "od: missing argument after -A\n", .{});
            if (args[i].len > 0) addr_radix = args[i][0];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-t")) {
            i += 1;
            if (i >= args.len) return core.die(1, "od: missing argument after -t\n", .{});
            if (args[i].len > 0) data_type = args[i][0];
            i += 1;
        } else return core.die(1, "od: unknown option: {s}\n", .{args[i]});
    }
    const files = args[i..];
    const alloc = std.heap.page_allocator;
    if (files.len == 0) {
        const data = core.readAll(alloc, 0, 1024 * 1024) catch return 1;
        defer alloc.free(data);
        dumpOctal(data, addr_radix, data_type);
    } else {
        for (files) |f| {
            const fd = core.openReadName(f) orelse {
                core.eprint("od: cannot open '{s}'\n", .{f});
                continue;
            };
            defer _ = core.c.close(fd);
            const data = core.readAll(alloc, fd, 1024 * 1024) catch continue;
            defer alloc.free(data);
            dumpOctal(data, addr_radix, data_type);
        }
    }
    return 0;
}
fn dumpOctal(data: []const u8, addr_radix: u8, data_type: u8) void {
    const bpl: usize = 16;
    var addr: usize = 0;
    var lb: [256]u8 = undefined;
    while (addr < data.len) {
        var pos: usize = 0;
        const an = fmtAddr(lb[pos..], addr, addr_radix);
        pos += an.len;
        var bi: usize = 0;
        while (bi < bpl and addr + bi < data.len) : (bi += 1) {
            lb[pos] = ' ';
            pos += 1;
            const bn = fmtByte(lb[pos..], data[addr + bi], data_type);
            pos += bn.len;
        }
        lb[pos] = '\n'; pos += 1;
        core.writeAll(1, lb[0..pos]);
        addr += bpl;
    }
    if (data.len > 0) {
        const an = fmtAddr(lb[0..], data.len, addr_radix);
        var pos: usize = an.len;
        lb[pos] = '\n'; pos += 1;
        core.writeAll(1, lb[0..pos]);
    }
}
fn fmtAddr(buf: []u8, addr: usize, radix: u8) []u8 {
    return switch (radix) {
        'd' => std.fmt.bufPrint(buf, "{d:7}", .{addr}) catch "",
        'x' => std.fmt.bufPrint(buf, "{x:7}", .{addr}) catch "",
        else => std.fmt.bufPrint(buf, "{o:7}", .{addr}) catch "",
    };
}
fn fmtByte(buf: []u8, byte: u8, dt: u8) []u8 {
    return switch (dt) {
        'd' => std.fmt.bufPrint(buf, "{d:3}", .{byte}) catch "",
        'x' => std.fmt.bufPrint(buf, "{x:2}", .{byte}) catch "",
        else => std.fmt.bufPrint(buf, "{o:3}", .{byte}) catch "",
    };
}
