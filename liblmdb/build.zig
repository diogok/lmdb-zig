const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const liblmdb = b.addStaticLibrary(.{
        .name = "liblmdb",
        .target = target,
        .optimize = optimize,
    });
    liblmdb.linkLibC();

    const src = b.path("src/libraries/liblmdb");
    liblmdb.addIncludePath(src);
    liblmdb.addCSourceFiles(.{
        .files = &.{
            "src/libraries/liblmdb/mdb.c",
            "src/libraries/liblmdb/midl.c",
        },
        .flags = &.{"-std=c99"},
    });
    liblmdb.installHeader(b.path("src/libraries/liblmdb/lmdb.h"), "lmdb.h");

    b.installArtifact(liblmdb);
}
