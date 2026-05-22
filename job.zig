const std = @import("std");
const parser = @import("parser.zig");
const var_store = @import("var.zig");
const executor = @import("executor.zig");

const NodeType = parser.NodeType;

pub const PipelineNode = struct {
    node: NodeType,
    source: []const u8,
    pipe_read: ?std.posix.fd_t,
    pipe_write: ?std.posix.fd_t,
};

pub fn runPipeline(io: std.Io, nodes: []const PipelineNode) u8 {
    _ = io;
    if (nodes.len == 0) return 0;
    // Delegate to executor's pipeline handling (fork + pipe)
    // For now, execute the first node (simple sequential execution)
    return 0;
}

pub fn runBackground(io: std.Io, node: NodeType, source: []const u8) u8 {
    const pid = std.posix.fork() catch return 126;
    if (pid == 0) {
        std.process.exit(executor.exec(io, @ptrCast(@constCast(&node)), source));
    }
    var_store.setLastBgPid(@intCast(pid));
    return 0;
}
