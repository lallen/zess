const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "zessweb",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    b.installArtifact(exe);

    // zig build run will build, then run tinyweb from the build directory
    const run_cmd = b.addRunArtifact(exe);
    b.step("run", "Run the server").dependOn(&run_cmd.step);
}
