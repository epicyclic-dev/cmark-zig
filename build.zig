// This file is licensed under the CC0 1.0 license.
// See: https://creativecommons.org/publicdomain/zero/1.0/legalcode

const std = @import("std");
const cmark_build = @import("./cmark.build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cmark = b.addModule("cmark", .{
        .root_source_file = .{ .path = "src/cmark.zig" },
    });
    cmark.addIncludePath(.{ .path = b.getInstallPath(.header, "") });

    const cmark_c = cmark_build.cmark_lib(b, .{
        .name = "cmark-c",
        .target = target,
        .optimize = optimize,
    });

    add_examples(b, .{
        .target = target,
        .cmark_module = cmark,
        .cmark_c = cmark_c,
    });
}

const ExampleOptions = struct {
    target: std.Build.ResolvedTarget,
    cmark_module: *std.Build.Module,
    cmark_c: *std.Build.Step.Compile,
};

const Example = struct {
    name: []const u8,
    file: []const u8,
};

const examples = [_]Example{
    .{ .name = "render_html", .file = "examples/render_html.zig" },
};

pub fn add_examples(b: *std.Build, options: ExampleOptions) void {
    const example_step = b.step("examples", "build examples");

    inline for (examples) |example| {
        const ex_exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.file },
            .target = options.target,
            .optimize = .Debug,
        });

        ex_exe.root_module.addImport("cmark", options.cmark_module);
        ex_exe.linkLibrary(options.cmark_c);

        const install = b.addInstallArtifact(ex_exe, .{});
        example_step.dependOn(&install.step);
    }
}
