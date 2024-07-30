const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule(
        "lmdb",
        .{
            .root_source_file = b.path("src/lmdb.zig"),
        },
    );

    const liblmdb = b.dependency("liblmdb", .{
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lmdb.zig"),
    });

    tests.linkLibrary(liblmdb.artifact("liblmdb"));

    const run_tests = b.addRunArtifact(tests);
    const run_tests_step = b.step("test", "Run tests");
    run_tests_step.dependOn(&run_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);
}
