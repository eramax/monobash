const std = @import("std");
const core = @import("core.zig");
pub const meta = core.AppletMeta{ .name = "hwclock", .main = main };

const RTC_RD_TIME: u32 = 0x80247009;
const RTC_SET_TIME: u32 = 0x4024700a;

const rtc_time = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};

fn readHwClock(rtc: *rtc_time) bool {
    const fd = core.c.open("/dev/rtc", core.c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = core.c.close(fd);
    return core.c.ioctl(fd, RTC_RD_TIME, rtc) == 0;
}

fn setHwClock(rtc: *const rtc_time) bool {
    const fd = core.c.open("/dev/rtc", core.c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = core.c.close(fd);
    return core.c.ioctl(fd, RTC_SET_TIME, @as(*const rtc_time, @ptrCast(rtc))) == 0;
}

fn rtcToEpoch(rtc: *const rtc_time) i64 {
    var tm = rtc.*;
    if (tm.tm_year < 70) tm.tm_year += 100;
    const y: i64 = @intCast(tm.tm_year + 1900);
    const m: i64 = @intCast(tm.tm_mon + 1);
    const d: i64 = @intCast(tm.tm_mday);
    const h: i64 = @intCast(tm.tm_hour);
    const min: i64 = @intCast(tm.tm_min);
    const s: i64 = @intCast(tm.tm_sec);

    const mon: i64 = if (m <= 2) @as(i64, @intCast(m + 12)) else m;
    const yr: i64 = if (m <= 2) y - 1 else y;
    const era: i64 = @divFloor(yr, 100);
    const doy: i64 = @divFloor(36525 * (yr + 4716), 100) + @divFloor(306 * (mon + 1), 10) + d - 1524;
    var epoch: i64 = doy - 719162;
    epoch = epoch * 86400 + h * 3600 + min * 60 + s;
    epoch -= @divFloor(era, 4) * 86400;
    return epoch;
}

fn epochToRtc(epoch: i64) rtc_time {
    var t = epoch;
    const s: c_int = @intCast(@mod(t, 86400));
    t = @divFloor(t, 86400);
    const h: c_int = @intCast(@divFloor(s, 3600));
    const min: c_int = @intCast(@divFloor(@mod(s, 3600), 60));
    const sec: c_int = @intCast(@mod(s, 60));

    t += 719162;
    const era: i64 = @divFloor(t, 146097);
    const doe: i64 = @mod(t, 146097);
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i64 = mp + @as(i64, if (mp < 10) 3 else -9);

    return .{
        .tm_sec = sec,
        .tm_min = min,
        .tm_hour = h,
        .tm_mday = @intCast(d),
        .tm_mon = @intCast(m - 1),
        .tm_year = @intCast(y - 1900),
        .tm_wday = 0,
        .tm_yday = 0,
        .tm_isdst = 0,
    };
}

pub fn main(args: [][]const u8) u8 {
    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "--systohc")) {
            var ts: core.c.struct_timespec = undefined;
            if (core.c.clock_gettime(core.c.CLOCK_REALTIME, &ts) != 0)
                return core.die(1, "hwclock: clock_gettime failed\n", .{});
            const rtc = epochToRtc(ts.tv_sec);
            if (!setHwClock(&rtc))
                return core.die(1, "hwclock: RTC_SET_TIME failed (need root?)\n", .{});
            return 0;
        }
        if (std.mem.eql(u8, args[1], "--hctosys")) {
            var rtc: rtc_time = undefined;
            if (!readHwClock(&rtc))
                return core.die(1, "hwclock: RTC_RD_TIME failed\n", .{});
            const epoch = rtcToEpoch(&rtc);
            var ts: core.c.struct_timespec = .{ .tv_sec = epoch, .tv_nsec = 0 };
            if (core.c.clock_settime(core.c.CLOCK_REALTIME, &ts) != 0)
                return core.die(1, "hwclock: clock_settime failed (need root?)\n", .{});
            return 0;
        }
        if (args[1][0] == '-')
            return core.die(1, "hwclock: unknown option '{s}'\n", .{args[1]});
    }

    var rtc: rtc_time = undefined;
    if (!readHwClock(&rtc)) {
        const d = core.openRead("/sys/class/rtc/rtc0/time");
        if (d == null) return core.die(1, "hwclock: cannot read hardware clock\n", .{});
        defer _ = core.c.close(d.?);
        const data = core.readAll(alloc, d.?, 64) catch return 1;
        defer alloc.free(data);
        const trimmed = std.mem.trimEnd(u8, data, " \n\r");
        core.writeAll(1, trimmed);
        core.writeAll(1, "\n");
        return 0;
    }

    var buf: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n", .{
        rtc.tm_year + 1900,
        rtc.tm_mon + 1,
        rtc.tm_mday,
        rtc.tm_hour,
        rtc.tm_min,
        rtc.tm_sec,
    }) catch return 1;
    core.writeAll(1, line);
    return 0;
}

const alloc = std.heap.page_allocator;
