const std = @import("std");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const NodeType = c.TSNode;
pub const TreeType = c.TSTree;

// tree_sitter_bash is defined in the grammar's parser.c
extern "c" fn tree_sitter_bash() *const c.TSLanguage;

var parser: ?*c.TSParser = null;

pub fn init() void {
    parser = c.ts_parser_new();
    if (parser) |p| {
        const ok = c.ts_parser_set_language(p, tree_sitter_bash());
        if (!ok) {
            @panic("tree-sitter: failed to set bash language");
        }
    } else {
        @panic("tree-sitter: failed to create parser");
    }
}

pub fn deinit() void {
    if (parser) |p| {
        c.ts_parser_delete(p);
        parser = null;
    }
}

pub fn parseString(source: [:0]const u8) ?*TreeType {
    return c.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len));
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !?*c.TSTree {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const source = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(source);
    // Make a null-terminated copy for tree-sitter
    const source_z = try allocator.alloc(u8, source.len + 1);
    defer allocator.free(source_z);
    @memcpy(source_z[0..source.len], source);
    source_z[source.len] = 0;
    return c.ts_parser_parse_string(parser, null, source_z.ptr, @intCast(source.len));
}

pub fn getNodeText(node: c.TSNode, source: []const u8) []const u8 {
    const start = c.ts_node_start_byte(node);
    const end = c.ts_node_end_byte(node);
    return source[@as(usize, @intCast(start))..@as(usize, @intCast(end))];
}

pub fn getNodeName(node: c.TSNode) []const u8 {
    return std.mem.sliceTo(c.ts_node_type(node), 0);
}

pub fn childCount(node: c.TSNode) usize {
    return @intCast(c.ts_node_child_count(node));
}

pub fn childAt(node: c.TSNode, index: usize) c.TSNode {
    return c.ts_node_child(node, @intCast(index));
}

pub fn namedChild(node: c.TSNode, index: usize) c.TSNode {
    return c.ts_node_named_child(node, @intCast(index));
}

pub fn namedChildCount(node: c.TSNode) usize {
    return @intCast(c.ts_node_named_child_count(node));
}

pub fn childByFieldName(node: c.TSNode, field_name: [:0]const u8) ?c.TSNode {
    const result = c.ts_node_child_by_field_name(node, field_name.ptr, @intCast(field_name.len));
    if (c.ts_node_is_null(result)) return null;
    return result;
}

pub fn childCountByFieldName(node: c.TSNode, field_name: [:0]const u8) usize {
    return @intCast(c.ts_node_child_count_by_field_name(node, field_name.ptr, @intCast(field_name.len)));
}

pub fn childrenByFieldName(node: c.TSNode, field_name: [:0]const u8, start_index: usize) c.TSNode {
    return c.ts_node_children_by_field_name(node, field_name.ptr, @intCast(field_name.len), @intCast(start_index));
}

pub fn isNull(node: c.TSNode) bool {
    return c.ts_node_is_null(node);
}

pub fn nextSibling(node: c.TSNode) c.TSNode {
    return c.ts_node_next_sibling(node);
}

pub fn prevSibling(node: c.TSNode) c.TSNode {
    return c.ts_node_prev_sibling(node);
}

pub fn namedNextSibling(node: c.TSNode) c.TSNode {
    return c.ts_node_next_named_sibling(node);
}

pub fn namedPrevSibling(node: c.TSNode) c.TSNode {
    return c.ts_node_prev_named_sibling(node);
}

pub fn rootNode(tree: *const c.TSTree) c.TSNode {
    return c.ts_tree_root_node(tree);
}

pub fn treeDelete(tree: *c.TSTree) void {
    c.ts_tree_delete(tree);
}
