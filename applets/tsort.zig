const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "tsort", .main = main };

fn getOrCreate(name: []const u8, map: *std.StringHashMap(usize), names: *std.ArrayListAligned([]u8, null), alloc: std.mem.Allocator) usize {
    if (map.get(name)) |id| return id;
    const id = names.items.len;
    const owned = alloc.dupe(u8, name) catch return 0;
    names.append(alloc, owned) catch return 0;
    map.put(owned, id) catch return 0;
    return id;
}

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    var node_to_id = std.StringHashMap(usize).init(alloc);
    defer node_to_id.deinit();
    var node_names: std.ArrayListAligned([]u8, null) = .empty;
    defer {
        for (node_names.items) |n| alloc.free(n);
        node_names.deinit(alloc);
    }
    var out_counts: std.ArrayListAligned(usize, null) = .empty;
    defer out_counts.deinit(alloc);
    var edges_from: std.ArrayListAligned(usize, null) = .empty;
    defer edges_from.deinit(alloc);
    var edges_to: std.ArrayListAligned(usize, null) = .empty;
    defer edges_to.deinit(alloc);

    var reader = core.LineReader.init(0);
    while (reader.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const a = it.next() orelse continue;
        const b = it.next() orelse continue;
        const aidx = getOrCreate(a, &node_to_id, &node_names, alloc);
        const bidx = getOrCreate(b, &node_to_id, &node_names, alloc);
        while (out_counts.items.len <= aidx)
            out_counts.append(alloc, 0) catch return 1;
        out_counts.items[aidx] += 1;
        edges_from.append(alloc, aidx) catch return 1;
        edges_to.append(alloc, bidx) catch return 1;
    }
    while (out_counts.items.len < node_names.items.len)
        out_counts.append(alloc, 0) catch return 1;

    if (node_names.items.len == 0) return 0;

    // Build adjacency list
    var adj_offsets = alloc.alloc(usize, node_names.items.len + 1) catch return 1;
    defer alloc.free(adj_offsets);
    var total_edges: usize = 0;
    for (out_counts.items, 0..) |cnt, i| {
        adj_offsets[i] = total_edges;
        total_edges += cnt;
    }
    adj_offsets[node_names.items.len] = total_edges;

    var adj = alloc.alloc(usize, total_edges) catch return 1;
    defer alloc.free(adj);

    var cur = alloc.alloc(usize, node_names.items.len) catch return 1;
    defer alloc.free(cur);
    @memcpy(cur, adj_offsets[0..node_names.items.len]);

    for (edges_from.items, edges_to.items) |f, t| {
        adj[cur[f]] = t;
        cur[f] += 1;
    }

    // Kahn's algorithm
    var in_deg = alloc.alloc(usize, node_names.items.len) catch return 1;
    defer alloc.free(in_deg);
    @memset(in_deg, 0);
    for (edges_to.items) |t| in_deg[t] += 1;

    var queue: std.ArrayListAligned(usize, null) = .empty;
    defer queue.deinit(alloc);
    for (0..node_names.items.len) |i| {
        if (in_deg[i] == 0) queue.append(alloc, i) catch return 1;
    }

    var out_buf: [8192]u8 = undefined;
    while (queue.items.len > 0) {
        const u = queue.orderedRemove(0);
        const name = node_names.items[u];
        const n = @min(name.len, out_buf.len - 1);
        @memcpy(out_buf[0..n], name[0..n]);
        out_buf[n] = '\n';
        core.writeAll(1, out_buf[0 .. n + 1]);

        var j = adj_offsets[u];
        while (j < adj_offsets[u + 1]) : (j += 1) {
            const v = adj[j];
            in_deg[v] -= 1;
            if (in_deg[v] == 0) queue.append(alloc, v) catch return 1;
        }
    }

    return 0;
}
