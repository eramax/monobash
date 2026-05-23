const core = @import("core.zig");
pub usingnamespace @import("true.zig");

/// Applet returns the AppletEntry for a given name, or null
pub fn lookup(name: []const u8) ?core.AppletEntry {
    // This comptime block enumerates all @imported applet modules
    // Each module should export `pub const meta`
    // We'll populate this properly after all applets are created
    return null;
}

/// Build the full applet table
pub fn all() []const core.AppletEntry {
    return &.{};
}

/// Run an applet by name with C-style args
pub fn run(name: []const u8, argc: c_int, argv: [*c][*c]u8) u8 {
    if (lookup(name)) |entry| {
        return @intCast(entry.mainFn(argc, argv));
    }
    return 127;
}
