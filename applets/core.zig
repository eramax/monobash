const std = @import("std");
const builtin = @import("builtin");

pub const AppletEntry = struct {
    name: []const u8,
    mainFn: *const fn (c_int, [*c][*c]u8) callconv(.c) c_int,
};

/// Define an applet module. Each applet file exports:
/// `pub const meta = AppletMeta{ .name = "cmd", .main = myMain };`
pub const AppletMeta = struct {
    name: []const u8,
    main: *const fn (args: [][]const u8) u8,
};

/// Build a C-compatible applet function from a Zig applet
pub fn wrap(meta: AppletMeta) AppletEntry {
    return .{
        .name = meta.name,
        .mainFn = struct {
            fn call(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
                const args = parseArgs(argc, argv);
                return @intCast(meta.main(args));
            }
        }.call,
    };
}

fn parseArgs(argc: c_int, argv: [*c][*c]u8) [][]const u8 {
    const alloc = std.heap.page_allocator;
    const result = alloc.alloc([]const u8, @intCast(argc)) catch return &.{};
    for (0..@intCast(argc)) |i| {
        result[i] = std.mem.sliceTo(argv[i], 0);
    }
    return result;
}

// ── Shared I/O helpers ──

/// Read all bytes from fd into a buffer (up to max_size)
pub fn readAll(allocator: std.mem.Allocator, fd: c_int, max_size: usize) ![]u8 {
    var buf = try allocator.alloc(u8, max_size);
    var pos: usize = 0;
    while (pos < max_size) {
        const n = c.read(fd, buf.ptr + pos, max_size - pos);
        if (n <= 0) break;
        pos += @intCast(n);
    }
    return buf[0..pos];
}

/// Write all bytes to fd (retry on partial write)
pub fn writeAll(fd: c_int, data: []const u8) void {
    var pos: usize = 0;
    while (pos < data.len) {
        const n = c.write(fd, data.ptr + pos, data.len - pos);
        if (n < 0) return;
        pos += @intCast(n);
    }
}

/// Write a string to stderr
pub fn eprint(comptime fmt: []const u8, args: anytype) void {
    const alloc = std.heap.page_allocator;
    const msg = std.fmt.allocPrint(alloc, fmt, args) catch return;
    defer alloc.free(msg);
    writeAll(2, msg);
}

pub fn die(exit_code: u8, comptime fmt: []const u8, args: anytype) u8 {
    eprint(fmt, args);
    return exit_code;
}

/// Buffered line reader
pub const LineReader = struct {
    buf: [65536]u8,
    pos: usize,
    end: usize,
    fd: c_int,
    eof: bool,

    pub fn init(fd: c_int) LineReader {
        return .{ .buf = undefined, .pos = 0, .end = 0, .fd = fd, .eof = false };
    }

    pub fn next(self: *LineReader) ?[]const u8 {
        while (true) {
            // Scan for newline in unconsumed portion
            var i = self.pos;
            while (i < self.end) : (i += 1) {
                if (self.buf[i] == '\n') {
                    const line = self.buf[self.pos..i];
                    self.pos = i + 1;
                    return line;
                }
            }
            // Need more data
            if (self.eof) {
                if (self.pos < self.end) {
                    const line = self.buf[self.pos..self.end];
                    self.pos = self.end;
                    return line;
                }
                return null;
            }
            // Shift buffer
            if (self.pos > 0) {
                std.mem.copyForwards(u8, self.buf[0..], self.buf[self.pos..self.end]);
                self.end -= self.pos;
                self.pos = 0;
            }
            if (self.end >= self.buf.len) {
                // Line too long, return as-is
                const line = self.buf[0..self.end];
                self.end = 0;
                return line;
            }
            const n = c.read(self.fd, @as([*]u8, @ptrCast(&self.buf)) + self.end, self.buf.len - self.end);
            if (n <= 0) {
                self.eof = true;
            } else {
                self.end += @intCast(n);
            }
        }
    }
};

/// Open a file for reading, returns fd or error
pub fn openRead(path: [:0]const u8) ?c_int {
    const fd = c.open(path.ptr, c.O_RDONLY);
    return if (fd >= 0) fd else null;
}

pub fn openReadName(name: []const u8) ?c_int {
    var buf: [4096:0]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    return openRead(buf[0..name.len :0]);
}

pub const FileIter = struct {
    files: [][]const u8,
    idx: usize,
    current_fd: c_int,
    current_name: []const u8,

    pub fn init(files: [][]const u8) FileIter {
        return .{ .files = files, .idx = 0, .current_fd = 0, .current_name = "" };
    }

    pub fn next(self: *FileIter) ?struct { fd: c_int, name: []const u8 } {
        if (self.current_fd > 0) {
            _ = c.close(self.current_fd);
            self.current_fd = 0;
        }
        if (self.idx == 0) {
            self.idx = 1;
            if (self.files.len <= 1) return null;
            // Skip program name
        }
        while (self.idx < self.files.len) {
            const name = self.files[self.idx];
            self.idx += 1;
            self.current_name = name;
            if (openReadName(name)) |fd| {
                self.current_fd = fd;
                return .{ .fd = fd, .name = name };
            } else {
                eprint("cannot open '{s}': No such file or directory\n", .{name});
            }
        }
        return null;
    }

    pub fn deinit(self: *FileIter) void {
        if (self.current_fd > 0) c.close(self.current_fd);
    }
};

pub extern "c" var environ: [*c][*c]u8;

pub const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/utsname.h");
    @cInclude("sys/wait.h");
    @cInclude("fcntl.h");
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("dirent.h");
    @cInclude("errno.h");
    @cInclude("time.h");
});
