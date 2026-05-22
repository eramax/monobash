const std = @import("std");
const parser = @import("parser.zig");
const var_store = @import("var.zig");
const expand = @import("expand.zig");
const executor = @import("executor.zig");
const builtins = @import("builtins.zig");
const applets = @import("applets.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const prog_name = std.fs.path.basename(args[0]);
    const is_shell = std.mem.indexOf(u8, prog_name, "monobash") != null or
        std.mem.eql(u8, prog_name, "bash") or
        std.mem.eql(u8, prog_name, "sh");

    if (!is_shell) {
        std.debug.print("monobash: {s}: command not found\n", .{prog_name});
        std.process.exit(127);
    }

    parser.init();
    defer parser.deinit();

    var_store.init(arena);
    defer var_store.deinit();

    executor.init(arena);

    if (args.len >= 3 and std.mem.eql(u8, args[1], "-c")) {
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

        // Get the directory from the path (or cwd for relative paths)
        const content = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), init.io, path, arena, .unlimited) catch {
            const msg = std.fmt.allocPrint(arena, "monobash: {s}: No such file or directory\n", .{path}) catch unreachable;
            _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, msg) catch {};
            std.process.exit(127);
        };

        var_store.setPositional(arena, &.{});
        var_store.set("0", path, false);

        // Skip shebang line if it starts with #!
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
    const c_stdio = @cImport({
        @cInclude("stdio.h");
    });

    var line_buf: [4096]u8 = undefined;
    var last_status: u8 = 0;

    while (true) {
        const prompt = if (last_status == 0) "monobash$ " else "monobash! ";
        _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, prompt) catch break;

        if (c_stdio.fgets(&line_buf, @as(c_int, @intCast(line_buf.len)), c_stdio.stdin)) |_| {
            // fgets includes trailing newline and null-terminates
            const raw = std.mem.sliceTo(&line_buf, 0);
            if (raw.len == 0) break;
            // Trim trailing whitespace/newlines
            var end = raw.len;
            while (end > 0 and (raw[end-1] == ' ' or raw[end-1] == '\t' or raw[end-1] == '\r' or raw[end-1] == '\n')) {
                end -= 1;
            }
            const line = raw[0..end];
            if (line.len == 0) continue;

            const line_z = try arena.dupeZ(u8, line);
            const tree = parser.parseString(line_z) orelse {
                const errmsg = "parse error\n";
                _ = std.Io.File.writeStreamingAll(std.Io.File.stderr(), init.io, errmsg) catch {};
                continue;
            };
            defer parser.treeDelete(tree);
            last_status = executor.exec(init.io, tree, line_z);
        } else {
            // EOF (Ctrl-D) or error
            break;
        }
    }

    _ = std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, "\n") catch {};
}
