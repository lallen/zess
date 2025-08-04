const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-hot-server",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(b.path("src"));
    b.installArtifact(exe);

    // Gzip the built binary
    const gzip_step = b.addSystemCommand(&[_][]const u8{
        "gzip",                       "-kf9",
        "zig-out/bin/zig-hot-server",
    });
    gzip_step.step.dependOn(b.getInstallStep());

    // Run the uncompressed binary
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Run the gzipped binary (decompress to zig-out/bin/zig-hot-server.run)
    const run_gz_step = b.addSystemCommand(&[_][]const u8{
        "sh",                                                                                                                                                   "-c",
        "gzip -dc zig-out/bin/zig-hot-server.gz > zig-out/bin/zig-hot-server.run && chmod +x zig-out/bin/zig-hot-server.run && zig-out/bin/zig-hot-server.run",
    });
    run_gz_step.step.dependOn(&gzip_step.step);

    // Expose build steps
    b.step("run", "Run the server").dependOn(&run_cmd.step);
    b.step("gzip", "Compress binary with gzip").dependOn(&gzip_step.step);
    b.step("run-gz", "Run gzipped binary").dependOn(&run_gz_step.step);
}
