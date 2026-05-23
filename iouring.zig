const std = @import("std");
const linux = std.os.linux;

/// Wrapper around Zig's std.os.linux.IoUring for async I/O.
/// Provides simplified read/write operations with automatic completion handling.
pub const Uring = struct {
    ring: linux.IoUring,

    pub fn init(entries: u16) !Uring {
        return .{ .ring = try linux.IoUring.init(entries, 0) };
    }

    pub fn deinit(self: *Uring) void {
        self.ring.deinit();
    }

    /// Sequential read (uses current file position, like pread with offset=-1)
    pub fn read(self: *Uring, fd: i32, buf: []u8) !usize {
        return self.pread(fd, buf, std.math.maxInt(u64));
    }

    /// Sequential write (uses current file position, like pwrite with offset=-1)
    pub fn write(self: *Uring, fd: i32, buf: []const u8) !usize {
        return self.pwrite(fd, buf, std.math.maxInt(u64));
    }

    /// Positional read (like pread)
    pub fn pread(self: *Uring, fd: i32, buf: []u8, offset: u64) !usize {
        _ = try self.ring.read(1, fd, .{ .buffer = buf }, offset);
        _ = try self.ring.submit();
        const cqe = try self.ring.copy_cqe();
        if (cqe.res < 0) return error.IoUringReadFailed;
        return @as(usize, @intCast(cqe.res));
    }

    /// Positional write (like pwrite)
    pub fn pwrite(self: *Uring, fd: i32, buf: []const u8, offset: u64) !usize {
        _ = try self.ring.write(1, fd, buf, offset);
        _ = try self.ring.submit();
        const cqe = try self.ring.copy_cqe();
        if (cqe.res < 0) return error.IoUringWriteFailed;
        return @as(usize, @intCast(cqe.res));
    }

    /// Open a file for reading (via openat)
    pub fn openRead(self: *Uring, path: [:0]const u8) !i32 {
        _ = try self.ring.openat(1, linux.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
        _ = try self.ring.submit();
        const cqe = try self.ring.copy_cqe();
        if (cqe.res < 0) return error.IoUringOpenFailed;
        return @as(i32, @intCast(cqe.res));
    }

    /// Close a file descriptor
    pub fn close(self: *Uring, fd: i32) !void {
        _ = try self.ring.close(1, fd);
        _ = try self.ring.submit();
        const cqe = try self.ring.copy_cqe();
        if (cqe.res < 0) return error.IoUringCloseFailed;
    }

    /// Submit all queued SQEs
    pub fn submit(self: *Uring) !void {
        _ = try self.ring.submit();
    }

    /// Submit and wait for at least one completion
    pub fn wait(self: *Uring) !void {
        _ = try self.ring.submit_and_wait(1);
    }

    /// Check if io_uring is available on this kernel
    pub fn isAvailable() bool {
        var ring = linux.IoUring.init(2, 0) catch return false;
        ring.deinit();
        return true;
    }
};

/// Read all bytes from fd into an allocated buffer using io_uring
pub fn readAll(uring: *Uring, allocator: std.mem.Allocator, fd: i32, max_size: usize) ![]u8 {
    var buf = try allocator.alloc(u8, max_size);
    var pos: usize = 0;
    while (pos < max_size) {
        const n = try uring.read(fd, buf[pos..]);
        if (n == 0) break;
        pos += n;
    }
    return buf[0..pos];
}

/// Write all bytes to fd using io_uring (retry on partial write)
pub fn writeAll(uring: *Uring, fd: i32, data: []const u8) !void {
    var pos: usize = 0;
    while (pos < data.len) {
        const n = try uring.write(fd, data[pos..]);
        pos += n;
    }
}

pub fn main() !void {
    if (!Uring.isAvailable()) {
        std.debug.print("io_uring NOT available on this system (kernel too old or disabled)\n", .{});
        std.process.exit(1);
    }
    std.debug.print("io_uring is available!\n", .{});

    var uring = try Uring.init(4);
    defer uring.deinit();

    // Test 1: Self-pipe loopback
    std.debug.print("Test 1: pipe write+read...\n", .{});
    {
        var fds: [2]i32 = undefined;
        const rc = linux.pipe(&fds);
        if (linux.errno(rc) != .SUCCESS) {
            std.debug.print("pipe() failed\n", .{});
            std.process.exit(1);
        }
        defer _ = linux.close(fds[0]);
        defer _ = linux.close(fds[1]);

        const msg = "Hello, io_uring from monobash!";
        const written = try uring.write(fds[1], msg);
        std.debug.print("  Wrote {d} bytes\n", .{written});

        var buf: [128]u8 = undefined;
        const n = try uring.read(fds[0], &buf);
        std.debug.print("  Read {d} bytes: \"{s}\"\n", .{ n, buf[0..n] });

        if (n != msg.len or !std.mem.eql(u8, msg, buf[0..n])) {
            std.debug.print("  FAIL: data mismatch\n", .{});
            std.process.exit(1);
        }
        std.debug.print("  PASS\n", .{});
    }

    // Test 2: readAll via io_uring
    std.debug.print("Test 2: readAll from /proc/self/status...\n", .{});
    {
        const path = "/proc/self/status";
        var buf: [4096:0]u8 = undefined;
        @memcpy(buf[0..path.len], path);
        buf[path.len] = 0;
        const fd = try uring.openRead(buf[0..path.len :0]);
        defer uring.close(fd) catch {};
        const alloc = std.heap.page_allocator;
        const data = try readAll(&uring, alloc, fd, 4096);
        defer alloc.free(data);
        std.debug.print("  Read {d} bytes from /proc/self/status\n", .{data.len});
        if (data.len == 0) {
            std.debug.print("  FAIL: empty read\n", .{});
            std.process.exit(1);
        }
        std.debug.print("  PASS\n", .{});
    }

    std.debug.print("\nAll io_uring tests PASSED\n", .{});
}
