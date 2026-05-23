const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("main.zig"),
        .link_libc = true,
    });

    const cflags = &.{ "-std=c11", "-D_GNU_SOURCE" };

    // tree-sitter library (lib.c includes all other .c files via #include)
    mod.addCSourceFile(.{
        .file = b.path("tree-sitter/lib/src/lib.c"),
        .flags = cflags,
    });
    mod.addIncludePath(b.path("tree-sitter/lib/include"));
    mod.addIncludePath(b.path("tree-sitter/lib/src"));

    // tree-sitter-bash grammar
    mod.addCSourceFile(.{
        .file = b.path("tree-sitter-bash/parser.c"),
        .flags = cflags,
    });
    mod.addCSourceFile(.{
        .file = b.path("tree-sitter-bash/scanner.c"),
        .flags = cflags,
    });
    mod.addIncludePath(b.path("tree-sitter-bash"));



    const exe = b.addExecutable(.{
        .name = "monobash",
        .root_module = mod,
    });

    b.installArtifact(exe);
}
