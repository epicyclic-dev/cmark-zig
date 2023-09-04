// This file is licensed under the CC0 1.0 license.
// See: https://creativecommons.org/publicdomain/zero/1.0/legalcode

const std = @import("std");
const cmark_build = @import("./cmark.build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cmark = b.addModule("cmark", .{
        .source_file = .{ .path = "src/cmark.zig" },
    });

    const cmark_c = cmark_build.cmark_lib(b, .{
        .target = target,
        .optimize = optimize,
    });

    _ = cmark;

    const cmarktest = b.addExecutable(.{
        .name = "cmtest",
        .root_source_file = .{ .path = "src/cmark.zig" },
    });

    cmarktest.linkLibrary(cmark_c);

    b.installArtifact(cmarktest);
}
