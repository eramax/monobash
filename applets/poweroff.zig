const reboot = @import("reboot.zig");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "poweroff", .main = reboot.mainPoweroff };
