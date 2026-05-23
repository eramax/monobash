const reboot = @import("reboot.zig");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "halt", .main = reboot.mainHalt };
