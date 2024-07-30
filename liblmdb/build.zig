const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lmdb = b.addStaticLibrary(.{
        .name = "liblmdb",
        .target = target,
        .optimize = optimize,
    });
    lmdb.linkLibC();

    const src = b.path("src/libraries/liblmdb");
    lmdb.addIncludePath(src);
    lmdb.addCSourceFiles(.{
        .files = &.{
            "src/libraries/liblmdb/mdb.c",
            "src/libraries/liblmdb/midl.c",
        },
        .flags = &.{"-std=c99"},
    });
    lmdb.installHeader(b.path("src/libraries/liblmdb/lmdb.h"), "lmdb.h");

    b.installArtifact(lmdb);
}
