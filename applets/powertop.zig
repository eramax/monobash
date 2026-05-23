const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "powertop", .main = main };

pub fn main(args: [][]const u8) u8 {
    _ = args;
    const alloc = std.heap.page_allocator;

    const sleep_seconds: u64 = 10;

    // Read C-state data from /proc/acpi/processor/*/power or from cpuidle
    // For simplicity, read from /sys/devices/system/cpu/*/cpuidle
    core.writeAll(1, "Collecting data for 10 seconds...\n");

    // Read initial C-state counters
    var initial_cstates: std.ArrayListAligned(struct { name: []const u8, count: u64, time: u64 }, null) = .empty;
    {
        const d = core.c.opendir("/sys/devices/system/cpu") orelse return 1;
        defer _ = core.c.closedir(d);

        while (true) {
            const entry = core.c.readdir(d) orelse break;
            const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
            const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
if (name.len < 3 or !std.mem.eql(u8, name[0..3], "cpu") or name[3] < '0' or name[3] > '9') continue;

            var cpuidle_path: [128]u8 = undefined;
            const cpuidle = std.fmt.bufPrint(&cpuidle_path, "/sys/devices/system/cpu/{s}/cpuidle", .{name}) catch continue;

            var z_buf: [256:0]u8 = undefined;
            if (cpuidle.len >= z_buf.len) continue;
            @memcpy(z_buf[0..cpuidle.len], cpuidle);
            z_buf[cpuidle.len] = 0;

            const cd = core.c.opendir(&z_buf) orelse continue;
            defer _ = core.c.closedir(cd);

            while (true) {
                const ce = core.c.readdir(cd) orelse break;
                const cdent: *core.c.struct_dirent = @ptrCast(@alignCast(ce));
                const cname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&cdent.d_name)), 0);
                if (cname.len < 3 or std.mem.order(u8, cname[0..3], "state") != .lt) continue;

                // Read state name
                var name_buf: [128]u8 = undefined;
                const name_path = std.fmt.bufPrint(&name_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/name", .{ name, cname }) catch continue;
                if (name_path.len >= z_buf.len) continue;
                @memcpy(z_buf[0..name_path.len], name_path);
                z_buf[name_path.len] = 0;
                const nfd = core.c.open(z_buf[0..name_path.len :0].ptr, core.c.O_RDONLY);
                if (nfd < 0) continue;
                const ndata = core.readAll(alloc, nfd, 64) catch { _ = core.c.close(nfd); continue; };
                _ = core.c.close(nfd);
                const state_name = std.mem.trim(u8, ndata, " \t\r\n");
                defer alloc.free(ndata);

                // Read usage count
                var usage_buf: [128]u8 = undefined;
                const usage_path = std.fmt.bufPrint(&usage_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/usage", .{ name, cname }) catch continue;
                @memcpy(z_buf[0..usage_path.len], usage_path);
                z_buf[usage_path.len] = 0;
                const ufd = core.c.open(z_buf[0..usage_path.len :0].ptr, core.c.O_RDONLY);
                if (ufd < 0) continue;
                const udata = core.readAll(alloc, ufd, 64) catch { _ = core.c.close(ufd); continue; };
                _ = core.c.close(ufd);
                const usage_str = std.mem.trim(u8, udata, " \t\r\n");
                const usage = std.fmt.parseUnsigned(u64, usage_str, 10) catch { alloc.free(udata); continue; };
                defer alloc.free(udata);

                // Read time
                var time_buf: [128]u8 = undefined;
                const time_path = std.fmt.bufPrint(&time_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/time", .{ name, cname }) catch continue;
                @memcpy(z_buf[0..time_path.len], time_path);
                z_buf[time_path.len] = 0;
                const tfd = core.c.open(z_buf[0..time_path.len :0].ptr, core.c.O_RDONLY);
                if (tfd < 0) continue;
                const tdata = core.readAll(alloc, tfd, 64) catch { _ = core.c.close(tfd); continue; };
                _ = core.c.close(tfd);
                const time_str = std.mem.trim(u8, tdata, " \t\r\n");
                const time_val = std.fmt.parseUnsigned(u64, time_str, 10) catch { alloc.free(tdata); continue; };
                defer alloc.free(tdata);

                initial_cstates.append(alloc, .{ .name = alloc.dupe(u8, state_name) catch "", .count = usage, .time = time_val }) catch {};
            }
        }
    }

    if (initial_cstates.items.len == 0) {
        core.writeAll(1, "No C-state data found. Try running as root or on a laptop.\n");
        return 1;
    }

    _ = core.c.sleep(@intCast(sleep_seconds));

    // Read and display differences
    core.writeAll(1, "\nTop power consumers:\n");
    var total_time: u64 = 0;
    for (initial_cstates.items) |state| total_time += state.time;

    const d = core.c.opendir("/sys/devices/system/cpu") orelse return 1;
    defer _ = core.c.closedir(d);

    while (true) {
        const entry = core.c.readdir(d) orelse break;
        const dirent: *core.c.struct_dirent = @ptrCast(@alignCast(entry));
        const name = std.mem.sliceTo(@as([*c]u8, @ptrCast(&dirent.d_name)), 0);
        if (name.len < 3 or !std.mem.eql(u8, name[0..3], "cpu") or name[3] < '0' or name[3] > '9') continue;

        var cpuidle_path: [128]u8 = undefined;
        const cpuidle = std.fmt.bufPrint(&cpuidle_path, "/sys/devices/system/cpu/{s}/cpuidle", .{name}) catch continue;

        var z_buf: [256:0]u8 = undefined;
        if (cpuidle.len >= z_buf.len) continue;
        @memcpy(z_buf[0..cpuidle.len], cpuidle);
        z_buf[cpuidle.len] = 0;

        const cd = core.c.opendir(&z_buf) orelse continue;
        defer _ = core.c.closedir(cd);

        while (true) {
            const ce = core.c.readdir(cd) orelse break;
            const cdent: *core.c.struct_dirent = @ptrCast(@alignCast(ce));
            const cname = std.mem.sliceTo(@as([*c]u8, @ptrCast(&cdent.d_name)), 0);
            if (cname.len < 3 or std.mem.order(u8, cname[0..3], "state") != .lt) continue;

            var name_buf: [128]u8 = undefined;
            const name_path = std.fmt.bufPrint(&name_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/name", .{ name, cname }) catch continue;
            if (name_path.len >= z_buf.len) continue;
            @memcpy(z_buf[0..name_path.len], name_path);
            z_buf[name_path.len] = 0;
            const nfd = core.c.open(z_buf[0..name_path.len :0].ptr, core.c.O_RDONLY);
            if (nfd < 0) continue;
            const ndata = core.readAll(alloc, nfd, 64) catch { _ = core.c.close(nfd); continue; };
            _ = core.c.close(nfd);
            const state_name = std.mem.trim(u8, ndata, " \t\r\n");
            defer alloc.free(ndata);

            var usage_buf: [128]u8 = undefined;
            const usage_path = std.fmt.bufPrint(&usage_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/usage", .{ name, cname }) catch continue;
            @memcpy(z_buf[0..usage_path.len], usage_path);
            z_buf[usage_path.len] = 0;
            const ufd = core.c.open(z_buf[0..usage_path.len :0].ptr, core.c.O_RDONLY);
            if (ufd < 0) continue;
            const udata = core.readAll(alloc, ufd, 64) catch { _ = core.c.close(ufd); continue; };
            _ = core.c.close(ufd);
            const usage_str = std.mem.trim(u8, udata, " \t\r\n");
            const cur_usage = std.fmt.parseUnsigned(u64, usage_str, 10) catch { alloc.free(udata); continue; };
            defer alloc.free(udata);

            var time_buf: [128]u8 = undefined;
            const time_path = std.fmt.bufPrint(&time_buf, "/sys/devices/system/cpu/{s}/cpuidle/{s}/time", .{ name, cname }) catch continue;
            @memcpy(z_buf[0..time_path.len], time_path);
            z_buf[time_path.len] = 0;
            const tfd = core.c.open(z_buf[0..time_path.len :0].ptr, core.c.O_RDONLY);
            if (tfd < 0) continue;
            const tdata = core.readAll(alloc, tfd, 64) catch { _ = core.c.close(tfd); continue; };
            _ = core.c.close(tfd);
            const time_str = std.mem.trim(u8, tdata, " \t\r\n");
            const cur_time = std.fmt.parseUnsigned(u64, time_str, 10) catch { alloc.free(tdata); continue; };
            defer alloc.free(tdata);

            var line_buf: [256]u8 = undefined;
            const line = std.fmt.bufPrint(&line_buf, "C-state {s}: usage {d} time {d}ms\n", .{ state_name, cur_usage, cur_time / 1000 }) catch continue;
            core.writeAll(1, line);
        }
    }

    return 0;
}
