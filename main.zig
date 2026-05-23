const std = @import("std");
const parser = @import("parser.zig");
const var_store = @import("var.zig");
const expand = @import("expand.zig");
const executor = @import("executor.zig");
const builtins = @import("builtins.zig");
const applets = @import("applets.zig");
const core = @import("applets/core.zig");
const history_mod = @import("history.zig");
const tui = @import("tui.zig");
const cimport = @import("cimport.zig");
const c = cimport.c;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const prog_name = std.fs.path.basename(args[0]);
    const is_shell = std.mem.indexOf(u8, prog_name, "monobash") != null or
        std.mem.eql(u8, prog_name, "bash") or
        std.mem.eql(u8, prog_name, "sh");

    if (!is_shell) {
        std.debug.print("bash: {s}: command not found\n", .{prog_name});
        std.process.exit(127);
    }

    parser.init();
    defer parser.deinit();

    var_store.init(arena);
    defer var_store.deinit();

    executor.init(arena);

    core.initUring(64) catch {};
    core.initCounters();

    // Check for --debug flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) core.debug = true;
    }

    if (args.len >= 3 and std.mem.eql(u8, args[1], "-c")) {
        var_store.command_flag = true;
        const cmd = args[2];
        const tree = parser.parseString(cmd) orelse {
            const msg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(2);
        };
        defer parser.treeDelete(tree);
        const status = executor.exec(init.io, tree, cmd);
        std.process.exit(status);
    }

    if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "-")) {
        const path = args[1];
        const content = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), init.io, path, arena, .unlimited) catch {
            const msg = std.fmt.allocPrint(arena, "bash: {s}: No such file or directory\n", .{path}) catch unreachable;
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(127);
        };
        var_store.setPositional(arena, &.{});
        _ = var_store.set("0", path, false);
        const script = if (std.mem.startsWith(u8, content, "#!"))
            (std.mem.indexOfScalar(u8, content, '\n') orelse return) + 1
        else
            0;
        const body = content[script..];
        const body_z = try arena.dupeZ(u8, body);
        const tree = parser.parseString(body_z) orelse {
            const msg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(2);
        };
        defer parser.treeDelete(tree);
        const status = executor.exec(init.io, tree, body);
        std.process.exit(status);
    }

    // Interactive / REPL mode
    var_store.interactive = true;

    var last_status: u8 = 0;

    // History
    var_store.setupHistory(arena);
    const hist_size_str = if (var_store.get("HISTSIZE")) |v| v.value else "1000";
    const hist_size = std.fmt.parseUnsigned(usize, hist_size_str, 10) catch 1000;
    const histfile = if (var_store.get("HISTFILE")) |v| v.value else "";
    var history = history_mod.History.init(arena, hist_size);
    history_mod.instance = &history;
    if (histfile.len > 0) history.load(histfile);

    var term = tui.Terminal.init();
    defer {
        if (histfile.len > 0) history.save(histfile);
        term.deinit();
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, "\n") catch {};
    }

    while (true) {
        const prompt = if (last_status == 0) "monobash$ " else "monobash! ";

        if (!term.have_terminal) {
            _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, prompt) catch break;
        }
        const line = tui.readLine(arena, &history, prompt, &term) orelse break;
        defer arena.free(line);

        if (line.len == 0) continue;

        history.add(line);
        if (histfile.len > 0) history.append(histfile, line);

        core.resetUringCounters();
        const line_z = arena.dupeZ(u8, line) catch continue;
        var ts_: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts_);
        var ru_before: c.struct_rusage = undefined;
        _ = c.getrusage(c.RUSAGE_CHILDREN, &ru_before);
        const tree = parser.parseString(line_z) orelse {
            const errmsg = "parse error\n";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, errmsg) catch {};
            continue;
        };
        defer parser.treeDelete(tree);
        last_status = executor.exec(init.io, tree, line_z);

        if (core.debug) {
            var ts2: c.struct_timespec = undefined;
            _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts2);
            const elapsed_ns = (@as(u64, @intCast(ts2.tv_sec)) * 1_000_000_000 + @as(u64, @intCast(ts2.tv_nsec))) - (@as(u64, @intCast(ts_.tv_sec)) * 1_000_000_000 + @as(u64, @intCast(ts_.tv_nsec)));
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            var buf: [256]u8 = undefined;
            const ctr = core.uringCounts();
            var ru_after: c.struct_rusage = undefined;
            _ = c.getrusage(c.RUSAGE_CHILDREN, &ru_after);
            const maxrss_kb = ru_after.unnamed_0.ru_maxrss - ru_before.unnamed_0.ru_maxrss;
            const s = std.fmt.bufPrint(&buf, " ── {d:.2}ms  {d}MB  io_uring: {d}W+{d}R  fallback: {d}W+{d}R\n", .{
                elapsed_ms,
                @as(f64, @floatFromInt(maxrss_kb)) / 1024.0,
                ctr.write_ok, ctr.read_ok,
                ctr.write_fallback, ctr.read_fallback,
            }) catch "";
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, s) catch {};
        }
    }
}
