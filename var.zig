const std = @import("std");
const c = @import("cimport.zig").c;

pub const ATTR_LCASE = 1;
pub const ATTR_UCASE = 2;
pub const ATTR_NAMEREF = 4;
pub const ATTR_INTEGER = 8;
pub const ATTR_READONLY = 16;
pub const ATTR_ARRAY = 32;

pub const VarValue = struct {
    value: []const u8,
    exported: bool,
    attributes: u8,
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
var job_commands: std.StringHashMap([]const u8) = undefined;
var positional_params: std.ArrayListAligned([]const u8, null) = .empty;

// Shell options (set -e, set -u, set -o pipefail, etc.)
pub var errexit: bool = false;
pub var nounset: bool = false;
pub var nounset_error: bool = false;
pub var pipefail: bool = false;
pub var interactive: bool = false;
pub var command_flag: bool = false;
pub var xtrace: bool = false;

// $FUNCNAME, $BASH_SOURCE, $BASH_LINENO stacks
pub var funcname_stack: std.ArrayListAligned([]const u8, null) = .empty;
pub var source_stack: std.ArrayListAligned([]const u8, null) = .empty;
pub var lineno_stack: std.ArrayListAligned(usize, null) = .empty;

// set -o additional options
pub var noclobber: bool = false;
pub var allexport: bool = false;
pub var notify: bool = false;
pub var ignoreeof: bool = false;
pub var monitor: bool = false;
pub var noglob: bool = false;
pub var noexec: bool = false;
pub var verbose: bool = false;
pub var vi_mode: bool = false;
pub var emacs_mode: bool = false;

// shopt options - additional 16+ options beyond the 4 in builtins.zig
pub var shopt_histexpand: bool = false;
pub var shopt_cmdhist: bool = true;
pub var shopt_cdable_vars: bool = false;
pub var shopt_cdspell: bool = false;
pub var shopt_checkhash: bool = false;
pub var shopt_checkwinsize: bool = false;
pub var shopt_globstar: bool = false;
pub var shopt_hostcomplete: bool = false;
pub var shopt_huponexit: bool = false;
pub var shopt_lithist: bool = false;
pub var shopt_mailwarn: bool = false;
pub var shopt_no_empty_cmd_completion: bool = false;
pub var shopt_progcomp: bool = false;
pub var shopt_promptvars: bool = false;
pub var shopt_sourcepath: bool = true;
pub var shopt_xpg_echo: bool = false;

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
    nameref_table = std.StringHashMap([]const u8).init(arena);
    dir_stack = std.ArrayListAligned([]const u8, null).empty;
    readonly_set = std.StringHashMap(void).init(arena);
    int_vars = std.StringHashMap(void).init(arena);

    // Initialize directory stack with PWD
    var cwd_buf: [4096]u8 = undefined;
    if (getcwd(&cwd_buf, cwd_buf.len)) |pwd_ptr| {
        const pwd = std.mem.sliceTo(pwd_ptr, 0);
        dir_stack.append(arena, allocValue(pwd)) catch {};
    }
    initJobTable();

    // Get HOME via C getenv
    const home = c_getenv("HOME") orelse "/";
    _ = set("IFS", " \t\n", false);
    const path = c_getenv("PATH") orelse "/usr/local/bin:/usr/bin:/bin";
    _ = set("PATH", path, false);
    _ = set("HOME", home, false);

    // Standard bash special variables
    _ = set("BASH_SUBSHELL", "0", false);
    var pid_buf: [16]u8 = undefined;
    const pid_str = std.fmt.bufPrint(&pid_buf, "{d}", .{@as(c_int, getpid())}) catch "0";
    _ = set("BASHPID", pid_str, false);

    // Bash compatibility variables
    _ = set("BASH_VERSION", "5.2.37(1)-monobash", false);
    _ = set("BASH_COMPAT", "5.2", false);
    _ = set("SECONDS", "0", false);

    // RANDOM — generate a random value 0-32767
    var random_buf: [16]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(time(null))) +% @as(u64, @intCast(getpid())));
    const random_val = prng.random().int(u16) & 0x7FFF;
    const random_str = std.fmt.bufPrint(&random_buf, "{d}", .{random_val}) catch "0";
    _ = set("RANDOM", random_str, false);

    // UID, EUID, PPID
    var uid_buf: [16]u8 = undefined;
    const uid_str = std.fmt.bufPrint(&uid_buf, "{d}", .{getuid()}) catch "0";
    _ = set("UID", uid_str, false);

    var euid_buf: [16]u8 = undefined;
    const euid_str = std.fmt.bufPrint(&euid_buf, "{d}", .{geteuid()}) catch "0";
    _ = set("EUID", euid_str, false);

    var ppid_buf: [16]u8 = undefined;
    const ppid_str = std.fmt.bufPrint(&ppid_buf, "{d}", .{getppid()}) catch "0";
    _ = set("PPID", ppid_str, false);

    // HOSTNAME — try environment first, fallback to gethostname()
    const hostname_env = c_getenv("HOSTNAME");
    if (hostname_env) |h| {
        _ = set("HOSTNAME", h, false);
    } else {
        var hostname_buf: [256]u8 = undefined;
        if (gethostname(&hostname_buf, hostname_buf.len) == 0) {
            const len = std.mem.indexOfScalar(u8, &hostname_buf, 0) orelse hostname_buf.len;
            _ = set("HOSTNAME", hostname_buf[0..len], false);
        } else {
            _ = set("HOSTNAME", "localhost", false);
        }
    }

    // SHLVL — inherit from parent and increment
    var shlvl_buf: [16]u8 = undefined;
    const parent_shlvl = c_getenv("SHLVL") orelse "0";
    const shlvl = std.fmt.parseInt(u32, parent_shlvl, 10) catch 0;
    const shlvl_str = std.fmt.bufPrint(&shlvl_buf, "{d}", .{shlvl + 1}) catch "1";
    _ = set("SHLVL", shlvl_str, false);

    // Initialize stacks
    funcname_stack = std.ArrayListAligned([]const u8, null).empty;
    source_stack = std.ArrayListAligned([]const u8, null).empty;
    lineno_stack = std.ArrayListAligned(usize, null).empty;
    // Push initial frame for top-level
    source_stack.append(arena, allocValue("")) catch {};
    lineno_stack.append(arena, 0) catch {};

    // Static / initial values
    _ = set("LINENO", "1", false);

    // EPOCHSECONDS
    var epoch_buf: [32]u8 = undefined;
    const epoch_str = std.fmt.bufPrint(&epoch_buf, "{d}", .{time(null)}) catch "0";
    _ = set("EPOCHSECONDS", epoch_str, false);

    // PWD — current working directory
    var pwd_buf: [4096]u8 = undefined;
    if (getcwd(&pwd_buf, pwd_buf.len)) |pwd_ptr| {
        const pwd = std.mem.sliceTo(pwd_ptr, 0);
        _ = set("PWD", pwd, false);
    }
    // OLDPWD — initially unset (bash behavior)
    _ = set("OLDPWD", "", false);

    // PIPESTATUS — initially empty
    _ = set("PIPESTATUS", "", false);
}

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
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
extern "c" fn getuid() c_int;
extern "c" fn geteuid() c_int;
extern "c" fn getppid() c_int;
extern "c" fn gethostname(name: [*]u8, len: usize) c_int;
extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn time(timer: ?*i64) i64;

pub fn set(name: []const u8, value: []const u8, exported: bool) bool {
    if (isReadonly(name)) return false;
    var attrs: u8 = 0;
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |v| {
            attrs = v.attributes;
            break;
        }
        s = scope.parent;
    }
    const final_value = applyAttributes(value, attrs);
    s = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |_| {
            scope.vars.put(name, .{ .value = final_value, .exported = exported, .attributes = attrs }) catch {};
            exportVar(name, final_value);
            return true;
        }
        s = scope.parent;
    }
    global_scope.vars.put(allocValue(name), .{ .value = final_value, .exported = exported, .attributes = attrs }) catch {};
    exportVar(name, final_value);
    return true;
}

pub fn setLocal(name: []const u8, value: []const u8, exported: bool) bool {
    if (isReadonly(name)) return false;
    var attrs: u8 = 0;
    if (global_scope.vars.get(name)) |v| {
        attrs = v.attributes;
    }
    const final_value = applyAttributes(value, attrs);
    global_scope.vars.put(allocValue(name), .{ .value = final_value, .exported = exported, .attributes = attrs }) catch {};
    exportVar(name, final_value);
    return true;
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
    // EPOCHREALTIME is dynamic — compute on each read
    if (std.mem.eql(u8, name, "EPOCHREALTIME")) {
        var ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}.{d:0>6}", .{
            ts.tv_sec,
            @divFloor(@as(u64, @intCast(ts.tv_nsec)), 1000),
        }) catch "0";
        return VarValue{ .value = allocValue(s), .exported = false, .attributes = 0 };
    }
    // Resolve namerefs (with loop limit for safety)
    var resolved = name;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        if (nameref_table.get(resolved)) |target| {
            resolved = target;
        } else {
            break;
        }
    }
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(resolved)) |v| return v;
        s = scope.parent;
    }
    return null;
}

pub fn setExport(name: []const u8, val: bool) void {
    _ = val;
    // Re-set the exported flag by re-setting the variable
    if (get(name)) |v| {
        _ = set(name, v.value, true);
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
        if (scope.vars.remove(name)) {
            var buf: [4096]u8 = undefined;
            if (name.len < buf.len) {
                @memcpy(buf[0..name.len], name);
                buf[name.len] = 0;
                _ = unsetenv(buf[0..name.len :0]);
            }
            return;
        }
        s = scope.parent;
    }
    // Also try unsetenv even if not in our scope (env-only var)
    var buf: [4096]u8 = undefined;
    if (name.len < buf.len) {
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        _ = unsetenv(buf[0..name.len :0]);
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

pub fn addJobWithCmd(pid: u32, cmd: []const u8) void {
    job_table.append(std.heap.page_allocator, pid) catch {};
    var key_buf: [16]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{d}", .{pid}) catch return;
    const cmd_copy = std.heap.page_allocator.dupe(u8, cmd) catch return;
    job_commands.put(allocValue(key), cmd_copy) catch {};
}

pub fn getJobCmd(pid: u32) ?[]const u8 {
    var key_buf: [16]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{d}", .{pid}) catch return null;
    return job_commands.get(key);
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
    job_commands = std.StringHashMap([]const u8).init(std.heap.page_allocator);
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

// Integer attribute tracking (declare -i)
var int_vars: std.StringHashMap(void) = undefined;

// Nameref tracking (declare -n)
pub var nameref_table: std.StringHashMap([]const u8) = undefined;

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

pub fn setIntVar(name: []const u8, val: bool) void {
    if (val) {
        int_vars.put(allocValue(name), {}) catch {};
    } else {
        _ = int_vars.remove(name);
    }
}

pub fn hasIntVar(name: []const u8) bool {
    return int_vars.contains(name);
}

pub fn setAttributes(name: []const u8, attrs: u8) void {
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |v| {
            scope.vars.put(name, .{ .value = v.value, .exported = v.exported, .attributes = attrs }) catch {};
            return;
        }
        s = scope.parent;
    }
}

pub fn getAttributes(name: []const u8) u8 {
    var s: ?*Scope = global_scope;
    while (s) |scope| {
        if (scope.vars.get(name)) |v| {
            return v.attributes;
        }
        s = scope.parent;
    }
    return 0;
}

pub fn setNameref(name: []const u8, target: []const u8) void {
    nameref_table.put(allocValue(name), allocValue(target)) catch {};
}

pub fn getNameref(name: []const u8) ?[]const u8 {
    return nameref_table.get(name);
}

fn applyAttributes(value: []const u8, attrs: u8) []const u8 {
    if (attrs & ATTR_LCASE != 0) {
        var buf: [4096]u8 = undefined;
        if (value.len > buf.len) return allocValue(value);
        for (value, 0..) |ch, i| {
            buf[i] = std.ascii.toLower(ch);
        }
        return allocValue(buf[0..value.len]);
    }
    if (attrs & ATTR_UCASE != 0) {
        var buf: [4096]u8 = undefined;
        if (value.len > buf.len) return allocValue(value);
        for (value, 0..) |ch, i| {
            buf[i] = std.ascii.toUpper(ch);
        }
        return allocValue(buf[0..value.len]);
    }
    return allocValue(value);
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

// FUNCNAME stack helpers
pub fn pushFuncName(name: []const u8) void {
    funcname_stack.append(global_arena.allocator(), allocValue(name)) catch {};
}

pub fn popFuncName() void {
    if (funcname_stack.items.len > 0) {
        _ = funcname_stack.pop();
    }
}

pub fn getFuncNameStack() []const []const u8 {
    return funcname_stack.items;
}

pub fn getFuncNameDepth() usize {
    return funcname_stack.items.len;
}

// BASH_SOURCE / BASH_LINENO stack helpers
pub fn pushSourceInfo(source: []const u8, lineno: usize) void {
    source_stack.append(global_arena.allocator(), allocValue(source)) catch {};
    lineno_stack.append(global_arena.allocator(), lineno) catch {};
}

pub fn popSourceInfo() void {
    if (source_stack.items.len > 0) {
        _ = source_stack.pop();
    }
    if (lineno_stack.items.len > 0) {
        _ = lineno_stack.pop();
    }
}

pub fn getSourceStack() []const []const u8 {
    return source_stack.items;
}

pub fn getLinenoStack() []const usize {
    return lineno_stack.items;
}

pub fn getSpecial(ch: u8) []const u8 {
    switch (ch) {
        '?' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{exit_status}) catch "0",
        '!' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{last_bg_pid}) catch "0",
        '$' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{@as(c_int, getpid())}) catch "0",
        '#' => return std.fmt.allocPrint(global_arena.allocator(), "{d}", .{positional_params.items.len}) catch "0",
        '-' => {
            // Build dynamic flags string reflecting shell state
            var buf: [16]u8 = undefined;
            var pos: usize = 0;
            if (interactive) { buf[pos] = 'i'; pos += 1; }
            buf[pos] = 'h'; pos += 1;
            if (errexit) { buf[pos] = 'e'; pos += 1; }
            if (nounset) { buf[pos] = 'u'; pos += 1; }
            if (xtrace) { buf[pos] = 'x'; pos += 1; }
            buf[pos] = 'B'; pos += 1;
            if (command_flag) { buf[pos] = 'c'; pos += 1; }
            return global_arena.allocator().dupe(u8, buf[0..pos]) catch "hBc";
        },
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
            if (ch >= '1' and ch <= '9') {
                const idx = ch - '1';
                if (idx < positional_params.items.len) {
                    return positional_params.items[idx];
                }
                return "";
            }
            return "";
        },
    }
}

pub fn setupHistory(_: std.mem.Allocator) void {
    if (get("HISTSIZE") == null) {
        _ = set("HISTSIZE", "1000", false);
    }
    if (get("HISTFILE") == null) {
        const home = if (get("HOME")) |h| h.value else "/root";
        var hf: [4096]u8 = undefined;
        const histfile = std.fmt.bufPrint(&hf, "{s}/.bash_history", .{home}) catch return;
        _ = set("HISTFILE", histfile, false);
    }
    if (get("HISTFILESIZE") == null) {
        _ = set("HISTFILESIZE", "1000", false);
    }
}
