const core = @import("core.zig");

const LINUX_REBOOT_CMD_RESTART: u32 = 0x01234567;
const LINUX_REBOOT_CMD_HALT: u32 = 0xCDEF0123;
const LINUX_REBOOT_CMD_POWER_OFF: u32 = 0x4321FEDC;
extern "c" fn reboot(cmd: u32) c_int;

fn doReboot(cmd: u32, name: []const u8) u8 {
    core.c.sync();
    _ = reboot(cmd);
    return core.die(1, "{s}: failed\n", .{name});
}

pub fn main(_: [][]const u8) u8 { return doReboot(LINUX_REBOOT_CMD_RESTART, "reboot"); }
pub fn mainHalt(_: [][]const u8) u8 { return doReboot(LINUX_REBOOT_CMD_HALT, "halt"); }
pub fn mainPoweroff(_: [][]const u8) u8 { return doReboot(LINUX_REBOOT_CMD_POWER_OFF, "poweroff"); }

pub const meta = core.AppletMeta{ .name = "reboot", .main = main };
