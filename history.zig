const std = @import("std");
const c = @import("cimport.zig").c;

pub var instance: ?*History = null;

pub const History = struct {
    lines: [][]const u8,
    count: usize,
    max: usize,
    pos: usize,
    current_idx: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) History {
        return .{
            .lines = allocator.alloc([]const u8, max_entries) catch &.{},
            .count = 0,
            .max = max_entries,
            .pos = 0,
            .current_idx = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *History) void {
        for (self.lines[0..self.count]) |line| self.allocator.free(line);
        self.allocator.free(self.lines);
    }

    pub fn add(self: *History, line: []const u8) void {
        if (line.len == 0) return;
        if (line.len > 4096) return;

        // Don't add duplicate of the last entry
        if (self.count > 0 and std.mem.eql(u8, self.lines[(self.count - 1) % self.max], line)) return;

        // Free oldest entry if buffer is full
        if (self.count >= self.max) {
            self.allocator.free(self.lines[self.count % self.max]);
        }
        self.lines[self.count % self.max] = self.allocator.dupe(u8, line) catch return;
        self.count += 1;
        self.current_idx = self.count;
    }

    pub fn getPrev(self: *History) ?[]const u8 {
        if (self.count == 0) return null;
        if (self.current_idx == 0) return null;
        self.current_idx -= 1;
        return self.lines[self.current_idx % self.max];
    }

    pub fn getNext(self: *History) ?[]const u8 {
        if (self.current_idx >= self.count) return null;
        self.current_idx += 1;
        if (self.current_idx >= self.count) return null;
        return self.lines[self.current_idx % self.max];
    }

    pub fn resetNav(self: *History) void {
        self.current_idx = self.count;
    }

    pub fn load(self: *History, path: []const u8) void {
        if (path.len == 0) return;
        const path_z = self.allocator.dupeZ(u8, path) catch return;
        defer self.allocator.free(path_z);
        const fd = c.open(path_z.ptr, c.O_RDONLY);
        if (fd < 0) return;
        defer _ = c.close(fd);

        var buf: [4096]u8 = undefined;
        var pos: usize = 0;
        while (true) {
            const n = c.read(fd, @as([*]u8, @ptrCast(&buf)) + pos, buf.len - pos - 1);
            if (n <= 0) break;
            pos += @as(usize, @intCast(n));
        }
        buf[pos] = 0;

        var i: usize = 0;
        while (i < pos) {
            var end = i;
            while (end < pos and buf[end] != '\n') end += 1;
            if (end > i) {
                self.add(buf[i..end]);
            }
            i = end + 1;
        }
    }

    pub fn append(self: *History, path: []const u8, line: []const u8) void {
        if (path.len == 0 or line.len == 0) return;
        const path_z = self.allocator.dupeZ(u8, path) catch return;
        defer self.allocator.free(path_z);
        const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c_uint, 0o600));
        if (fd < 0) return;
        defer _ = c.close(fd);
        _ = c.write(fd, line.ptr, line.len);
        _ = c.write(fd, "\n", 1);
    }

    pub fn save(self: *History, path: []const u8) void {
        if (path.len == 0) return;
        const path_z = self.allocator.dupeZ(u8, path) catch return;
        defer self.allocator.free(path_z);
        const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o600));
        if (fd < 0) return;
        defer _ = c.close(fd);

        const start = if (self.count > self.max) self.count - self.max else 0;
        var i = start;
        while (i < self.count) {
            const line = self.lines[i % self.max];
            _ = c.write(fd, line.ptr, line.len);
            _ = c.write(fd, "\n", 1);
            i += 1;
        }
    }
};
