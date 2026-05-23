const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lmdb_upstream = b.dependency("lmdb", .{});
    const lmdb_src = lmdb_upstream.path("libraries/liblmdb");

    const liblmdb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    liblmdb_mod.addIncludePath(lmdb_src);
    liblmdb_mod.addCSourceFiles(.{
        .root = lmdb_src,
        .files = &.{
            "mdb.c",
            "midl.c",
        },
        .flags = &.{"-std=c99"},
    });

    const liblmdb = b.addLibrary(.{
        .name = "liblmdb",
        .linkage = .static,
        .root_module = liblmdb_mod,
    });
    liblmdb.installHeader(lmdb_upstream.path("libraries/liblmdb/lmdb.h"), "lmdb.h");
    b.installArtifact(liblmdb);

    const translate_c = b.addTranslateC(.{
        .root_source_file = lmdb_upstream.path("libraries/liblmdb/lmdb.h"),
        .target = target,
        .optimize = optimize,
    });
    const c_mod = translate_c.createModule();

    const lmdb_mod = b.addModule("lmdb", .{
        .root_source_file = b.path("src/lmdb.zig"),
        .target = target,
        .optimize = optimize,
    });
    lmdb_mod.addImport("c", c_mod);
    lmdb_mod.linkLibrary(liblmdb);

    const tests = b.addTest(.{
        .root_module = lmdb_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const run_tests_step = b.step("test", "Run tests");
    run_tests_step.dependOn(&run_tests.step);

    const update_docs = b.addUpdateSourceFiles();
    const emitted_docs = tests.getEmittedDocs();
    for ([_][]const u8{ "index.html", "main.js", "main.wasm", "sources.tar" }) |name| {
        update_docs.addCopyFileToSource(
            emitted_docs.path(b, name),
            b.pathJoin(&.{ "docs", name }),
        );
    }

    const docs_step = b.step("docs", "Copy generated documentation to ./docs");
    docs_step.dependOn(&update_docs.step);
}
