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

    _ = zing_lib_mod;
}
