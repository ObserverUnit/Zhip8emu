const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_atrifact = raylib_dep.artifact("raylib");

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("raylib", raylib);
    lib_mod.addImport("raygui", raygui);

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zhip8emu_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zhip8emu",
        .root_module = lib_mod,
    });

    lib.linkLibrary(raylib_atrifact);
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zhip8emu",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // tests step
    const unit_tests = b.addTest(.{
        .root_module = tests_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // check step (better ZLS experience)
    const exe_check = b.addExecutable(.{
        .root_module = exe_mod,
        .name = "zhip8emu",
    });

    const check_step = b.step("check", "Run all checks");
    check_step.dependOn(&exe_check.step);
}
