const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "httpd", .main = main };

fn mimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html") or std.mem.endsWith(u8, path, ".htm")) return "text/html";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".ico")) return "image/x-icon";
    if (std.mem.endsWith(u8, path, ".txt")) return "text/plain";
    if (std.mem.endsWith(u8, path, ".pdf")) return "application/pdf";
    if (std.mem.endsWith(u8, path, ".zip")) return "application/zip";
    return "application/octet-stream";
}

fn serveFile(client: c_int, doc_root: []const u8, path: []const u8) void {
    const alloc = std.heap.page_allocator;

    if (std.mem.indexOf(u8, path, "..") != null) {
        const resp = "HTTP/1.0 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nForbidden";
        _ = core.c.send(client, resp.ptr, resp.len, 0);
        return;
    }

    const fpath = if (path.len == 0 or path[0] != '/')
        std.fmt.allocPrint(alloc, "{s}/{s}", .{ doc_root, path }) catch return
    else
        std.fmt.allocPrint(alloc, "{s}{s}", .{ doc_root, path }) catch return;
    defer alloc.free(fpath);

    const resolved = std.fs.path.resolve(alloc, &.{ fpath }) catch return;
    defer alloc.free(resolved);

    if (!std.mem.startsWith(u8, resolved, doc_root)) {
        const resp = "HTTP/1.0 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nForbidden";
        _ = core.c.send(client, resp.ptr, resp.len, 0);
        return;
    }

    var st: core.c.struct_stat = undefined;
    const zd = alloc.dupeZ(u8, resolved) catch return;
    defer alloc.free(zd);
    if (core.c.stat(zd.ptr, &st) < 0) {
        const resp = "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nNot Found";
        _ = core.c.send(client, resp.ptr, resp.len, 0);
        return;
    }

    if (core.c.S_ISDIR(st.st_mode)) {
        const index_path = std.fmt.allocPrint(alloc, "{s}/index.html", .{resolved}) catch return;
        defer alloc.free(index_path);
        const iz = alloc.dupeZ(u8, index_path) catch return;
        defer alloc.free(iz);
        if (core.c.stat(iz.ptr, &st) >= 0 and core.c.S_ISREG(st.st_mode)) {
            serveFile(client, doc_root, index_path[doc_root.len..]);
            return;
        }
        var resp: [512]u8 = undefined;
        const body = std.fmt.bufPrint(&resp, "<html><body><h1>Index of {s}</h1></body></html>", .{path}) catch {
            const r = "HTTP/1.0 500 Error\r\nContent-Length: 0\r\n\r\n";
            _ = core.c.send(client, r.ptr, r.len, 0);
            return;
        };
        var hdr: [256]u8 = undefined;
        const h = std.fmt.bufPrint(&hdr, "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: {d}\r\n\r\n", .{body.len}) catch return;
        _ = core.c.send(client, h.ptr, h.len, 0);
        _ = core.c.send(client, body.ptr, body.len, 0);
        return;
    }

    const fd = core.c.open(zd.ptr, core.c.O_RDONLY);
    if (fd < 0) {
        const resp = "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nNot Found";
        _ = core.c.send(client, resp.ptr, resp.len, 0);
        return;
    }
    defer _ = core.c.close(fd);

    const mt = mimeType(resolved);
    var hdr: [512]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.0 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n", .{ mt, st.st_size }) catch return;
    _ = core.c.send(client, h.ptr, h.len, 0);

    while (true) {
        const data = core.readAll(std.heap.page_allocator, fd, 16384) catch break;
        defer std.heap.page_allocator.free(data);
        if (data.len == 0) break;
        _ = core.c.send(client, data.ptr, data.len, 0);
    }
}

pub fn main(args: [][]const u8) u8 {
    var port: u16 = 80;
    var doc_root: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch return core.die(1, "httpd: invalid port\n", .{});
        } else if (std.mem.eql(u8, args[i], "-h") and i + 1 < args.len) {
            i += 1;
            doc_root = args[i];
        } else return core.die(1, "usage: httpd -p PORT -h DIR\n", .{});
    }

    const sock = core.c.socket(core.c.AF_INET, core.c.SOCK_STREAM, 0);
    if (sock < 0) return core.die(1, "httpd: socket\n", .{});

    var opt: c_int = 1;
    _ = core.c.setsockopt(sock, core.c.SOL_SOCKET, core.c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: core.c.struct_sockaddr_in = std.mem.zeroes(core.c.struct_sockaddr_in);
    addr.sin_family = core.c.AF_INET;
    addr.sin_addr.s_addr = core.c.INADDR_ANY;
    addr.sin_port = core.c.htons(port);

    if (core.c.bind(sock, .{ .__sockaddr_in__ = @ptrCast(&addr) }, @sizeOf(@TypeOf(addr))) < 0)
        return core.die(1, "httpd: bind\n", .{});
    if (core.c.listen(sock, 10) < 0)
        return core.die(1, "httpd: listen\n", .{});

    var msg: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&msg, "httpd: listening on port {d}, root {s}\n", .{ port, doc_root }) catch "httpd: started\n";
    core.writeAll(1, m);

    while (true) {
        var cli_addr: core.c.struct_sockaddr_in = undefined;
        var cli_len: core.c.socklen_t = @sizeOf(@TypeOf(cli_addr));
        const client = core.c.accept(sock, .{ .__sockaddr_in__ = @ptrCast(&cli_addr) }, &cli_len);
        if (client < 0) continue;

        var buf: [4096]u8 = undefined;
        const rlen = core.c.recv(client, &buf, buf.len, 0);
        if (rlen > 0) {
            const req = buf[0..@as(usize, @intCast(rlen))];
            if (std.mem.startsWith(u8, req, "GET ")) {
                const path_start = req[4..];
                const spc = std.mem.indexOfScalar(u8, path_start, ' ') orelse {
                    _ = core.c.close(client);
                    continue;
                };
                const path = path_start[0..spc];
                serveFile(client, doc_root, path);
            }
        }
        _ = core.c.close(client);
    }
}
