const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const argparse_dep = b.dependency("argparse", .{
        .target = target,
        .optimize = optimize,
    });
    const tasks_core_dep = b.dependency("tasks_core", .{});
    const tasks_render_dep = b.dependency("tasks_render", .{});
    const tasks_store_json_dep = b.dependency("tasks_store_json", .{});

    const mod = b.addModule("tasks-cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("argparse", argparse_dep.module("argparse"));
    mod.addImport("tasks-core", tasks_core_dep.module("tasks-core"));
    mod.addImport("tasks-render", tasks_render_dep.module("tasks-render"));
    mod.addImport("tasks-store-json", tasks_store_json_dep.module("tasks-store-json"));

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
