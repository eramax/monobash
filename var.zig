const std = @import("std");

pub const VarValue = struct {
    value: []const u8,
    exported: bool,
};

pub const Scope = struct {
    vars: std.StringHashMap(VarValue),
    parent: ?*Scope,
};

var global_arena: std.heap.ArenaAllocator = undefined;
var global_scope: *Scope = undefined;
var exit_status: u8 = 0;
var last_bg_pid: u32 = 0;
var job_table: std.ArrayListAligned(u32, null) = .empty;
var positional_params: std.ArrayListAligned([]const u8, null) = .empty;

// Shell options (set -e, set -u, set -o pipefail, etc.)
pub var errexit: bool = false;
pub var nounset: bool = false;
pub var pipefail: bool = false;

pub fn init(allocator: std.mem.Allocator) void {
    global_arena = std.heap.ArenaAllocator.init(allocator);
    const arena = global_arena.allocator();
    global_scope = arena.create(Scope) catch @panic("oom");
    global_scope.* = .{
        .vars = std.StringHashMap(VarValue).init(arena),
        .parent = null,
    };
    positional_params = std.ArrayListAligned([]const u8, null).empty;
    alias_table = std.StringHashMap([]const u8).init(arena);
    dir_stack = std.ArrayListAligned([]const u8, null).empty;
    readonly_set = std.StringHashMap(void).init(arena);
    initJobTable();

    // Get HOME via C getenv
    const home = c_getenv("HOME") orelse "/";
    set("IFS", " \t\n", false);
    set("PATH", "/usr/local/bin:/usr/bin:/bin", false);
    set("HOME", home, false);

    // Standard bash special variables
    set("BASH_SUBSHELL", "0", false);
    var pid_buf: [16]u8 = undefined;
    const pid_str = std.fmt.bufPrint(&pid_buf, "{d}", .{@as(c_int, getpid())}) catch "0";
    set("BASHPID", pid_str, false);
}

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
fn c_getenv(name: [:0]const u8) ?[]const u8 {
    const ptr = getenv(name.ptr);
    return if (ptr) |p| std.mem.sliceTo(p, 0) else null;
}

pub fn deinit() void {
    global_arena.deinit();
}

pub fn currentScope() *Scope {
    return global_scope;
}

pub fn pushScope() void {
    const arena = global_arena.allocator();
    const new_scope = arena.create(Scope) catch @panic("oom");
    new_scope.* = .{
        .vars = std.StringHashMap(VarValue).init(arena),
        .parent = global_scope,
    };
    global_scope = new_scope;
}

pub fn popScope() void {
    if (global_scope.parent) |parent| {
        global_scope = parent;
    }
}

fn allocValue(s: []const u8) []const u8 {
    return global_arena.allocator().dupe(u8, s) catch @panic("oom");
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn getpid() c_int;

pub fn set(name: []const u8, value: []const u8, exported: bool) void {
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |_| {
            scope.vars.put(name, .{ .value = allocValue(value), .exported = exported }) catch {};
            exportVar(name, value);
            return;
        }
        s = scope.parent;
    }
    global_scope.vars.put(allocValue(name), .{ .value = allocValue(value), .exported = exported }) catch {};
    exportVar(name, value);
}

pub fn setLocal(name: []const u8, value: []const u8, exported: bool) void {
    global_scope.vars.put(allocValue(name), .{ .value = allocValue(value), .exported = exported }) catch {};
    exportVar(name, value);
}

fn exportVar(name: []const u8, value: []const u8) void {
    var nbuf: [4096]u8 = undefined;
    var vbuf: [4096]u8 = undefined;
    if (name.len >= nbuf.len or value.len >= vbuf.len) return;
    @memcpy(nbuf[0..name.len], name);
    nbuf[name.len] = 0;
    @memcpy(vbuf[0..value.len], value);
    vbuf[value.len] = 0;
    _ = setenv(nbuf[0..name.len :0], vbuf[0..value.len :0], 1);
}

pub fn get(name: []const u8) ?VarValue {
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |v| return v;
        s = scope.parent;
    }
    return null;
}

pub fn setExport(name: []const u8, val: bool) void {
    _ = val;
    // Re-set the exported flag by re-setting the variable
    if (get(name)) |v| {
        set(name, v.value, true);
    }
}

pub fn setReadonlyFlag(name: []const u8, val: bool) void {
    setReadonly(name, val);
}

pub fn getAllocator() std.mem.Allocator {
    return global_arena.allocator();
}

pub fn unset(name: []const u8) void {
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.remove(name)) return;
        s = scope.parent;
    }
}

pub fn setExitStatus(status: u8) void {
    exit_status = status;
}

pub fn getExitStatus() u8 {
    return exit_status;
}

pub fn setLastBgPid(pid: u32) void {
    last_bg_pid = pid;
}

pub fn getLastBgPid() u32 {
    return last_bg_pid;
}

pub fn addJob(pid: u32) void {
    job_table.append(std.heap.page_allocator, pid) catch {};
}

pub fn removeJob(pid: u32) void {
    for (job_table.items, 0..) |jp, i| {
        if (jp == pid) {
            _ = job_table.swapRemove(i);
            return;
        }
    }
}

pub fn getJobs() []const u32 {
    return job_table.items;
}

pub fn initJobTable() void {
    job_table = std.ArrayListAligned(u32, null).empty;
}

pub fn getPositional() std.ArrayListAligned([]const u8, null) {
    return positional_params;
}

pub fn getPositionalValue(idx: usize) []const u8 {
    if (idx < positional_params.items.len) {
        return positional_params.items[idx];
    }
    return "";
}

pub fn setPositional(arena_alloc: std.mem.Allocator, args: [][]const u8) void {
    positional_params = std.ArrayListAligned([]const u8, null).empty;
    for (args) |a| {
        positional_params.append(arena_alloc, a) catch {};
    }
    // Export to environment so wordpexp can find them
    exportPositional();
}

fn exportPositional() void {
    for (positional_params.items, 0..) |p, i| {
        // Export $1, $2, etc. to environment so wordpexp can find them
        const idx = i + 1;
        var nbuf: [16]u8 = undefined;
        const nstr = std.fmt.bufPrint(&nbuf, "{d}", .{@as(u64, idx)}) catch continue;
        nbuf[nstr.len] = 0;
        var vbuf: [4096]u8 = undefined;
        if (p.len >= vbuf.len) continue;
        @memcpy(vbuf[0..p.len], p);
        vbuf[p.len] = 0;
        _ = setenv(nbuf[0..nstr.len :0], vbuf[0..p.len :0], 1);
    }
}

// Alias support
var alias_table: std.StringHashMap([]const u8) = undefined;

pub const AliasEntry = struct { name: []const u8, value: []const u8 };

pub fn getAliases() []const AliasEntry {
    var result = std.ArrayListAligned(AliasEntry, null).empty;
    var it = alias_table.iterator();
    while (it.next()) |entry| {
        result.append(global_arena.allocator(), .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* }) catch {};
    }
    return result.items;
}

pub fn setAlias(name: []const u8, value: []const u8) void {
    alias_table.put(allocValue(name), allocValue(value)) catch {};
}

pub fn removeAlias(name: []const u8) void {
    _ = alias_table.remove(name);
}

pub fn getAlias(name: []const u8) ?[]const u8 {
    if (alias_table.get(name)) |v| return v;
    return null;
}

// Directory stack
var dir_stack: std.ArrayListAligned([]const u8, null) = .empty;

pub fn getDirStack() []const []const u8 {
    return dir_stack.items;
}

pub fn pushDir(dir: []const u8) void {
    dir_stack.append(global_arena.allocator(), allocValue(dir)) catch {};
}

pub fn popDir() void {
    if (dir_stack.items.len > 0) {
        _ = dir_stack.pop();
    }
}

// Readonly tracking
var readonly_set: std.StringHashMap(void) = undefined;

pub fn setReadonly(name: []const u8, val: bool) void {
    if (val) {
        readonly_set.put(allocValue(name), {}) catch {};
    } else {
        _ = readonly_set.remove(name);
    }
}

pub fn isReadonly(name: []const u8) bool {
    return readonly_set.contains(name);
}

// Iterator support for listing all variables
pub const VarEntry = struct { name: []const u8, value: []const u8 };

pub fn allVars() []const VarEntry {
    var result = std.ArrayListAligned(VarEntry, null).empty;
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        var it = scope.vars.iterator();
        while (it.next()) |entry| {
            result.append(global_arena.allocator(), .{ .name = entry.key_ptr.*, .value = entry.value_ptr.*.value }) catch {};
        }
        s = scope.parent;
    }
    return result.items;
}

pub fn getSpecial(c: u8) []const u8 {
    switch (c) {
        '?' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{exit_status}) catch "0",
        '!' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{last_bg_pid}) catch "0",
        '$' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{@as(c_int, getpid())}) catch "0",
        '#' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{positional_params.items.len}) catch "0",
        '-' => return "hB",
        '@' => {
            // Return positional params joined by space
            if (positional_params.items.len == 0) return "";
            var result = std.ArrayListAligned(u8, null).empty;
            for (positional_params.items, 0..) |p, i| {
                if (i > 0) result.append(global_arena.allocator(), ' ') catch {};
                result.appendSlice(global_arena.allocator(), p) catch {};
            }
            return result.items;
        },
        '*' => {
            if (positional_params.items.len == 0) return "";
            var result = std.ArrayListAligned(u8, null).empty;
            for (positional_params.items, 0..) |p, i| {
                if (i > 0) result.append(global_arena.allocator(), ' ') catch {};
                result.appendSlice(global_arena.allocator(), p) catch {};
            }
            return result.items;
        },
        '0' => {
            if (get("0")) |v| return v.value;
            return "monobash";
        },
        else => {
            // Check positional params: '1'..'9' map to params[0]..params[8]
            if (c >= '1' and c <= '9') {
                const idx = c - '1';
                if (idx < positional_params.items.len) {
                    return positional_params.items[idx];
                }
                return "";
            }
            return "";
        },
    }
}
