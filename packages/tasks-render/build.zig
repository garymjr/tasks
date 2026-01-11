const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const tasks_core_dep = b.dependency("tasks_core", .{});

    const mod = b.addModule("tasks-render", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("tasks-core", tasks_core_dep.module("tasks-core"));

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
