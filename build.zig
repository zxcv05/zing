const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Lib Module
    const zing_lib_mod = b.addModule("zing", .{
        .root_source_file = b.path("src/zinglib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zing_test = b.addTest(.{
        .root_module = zing_lib_mod,
    });

    const run_test = b.addRunArtifact(zing_test);
    const run_step = b.step("test", "Test");

    run_step.dependOn(&run_test.step);
}
