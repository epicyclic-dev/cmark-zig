// This file is licensed under the CC0 1.0 license.
// See: https://creativecommons.org/publicdomain/zero/1.0/legalcode

const std = @import("std");

const CmarkBuildOptions = struct {
    name: []const u8 = "cmark-c",
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn cmark_lib(
    b: *std.Build,
    options: CmarkBuildOptions,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = options.name,
        .target = options.target,
        .optimize = options.optimize,
    });

    const cflags = [_][]const u8{};

    lib.linkLibC();
    lib.addCSourceFiles(&common_sources, &cflags);
    lib.addIncludePath(.{ .path = cmark_src_prefix ++ "include" });

    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = .{ .path = cmark_src_prefix ++ "config.h.in" } },
    }, .{
        .HAVE_STDBOOL_H = void{},
        .HAVE___ATTRIBUTE__ = void{},
        .HAVE___BUILTIN_EXPECT = void{},
    });

    const cmark_version_h = b.addConfigHeader(.{
        .style = .{ .cmake = .{ .path = cmark_src_prefix ++ "cmark_version.h.in" } },
    }, .{
        .PROJECT_VERSION_MAJOR = 0,
        .PROJECT_VERSION_MINOR = 30,
        .PROJECT_VERSION_PATCH = 3,
    });

    lib.addConfigHeader(config_h);
    lib.addConfigHeader(cmark_version_h);
    lib.addIncludePath(.{ .path = cmark_zig_prefix });
    lib.installConfigHeader(cmark_version_h, .{ .dest_rel_path = "cmark_version.h" });

    inline for (install_headers) |header| {
        lib.installHeader(header.base_dir ++ header.name, header.name);
    }

    b.installArtifact(lib);

    return lib;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = cmark_lib(b, .{ .target = target, .optimize = optimize });
}

const cmark_src_prefix = "deps/cmark/src/";
const cmark_zig_prefix = "src/";

const Header = struct {
    base_dir: [:0]const u8,
    name: [:0]const u8,
};

const install_headers = [_]Header{
    .{ .base_dir = cmark_src_prefix, .name = "cmark.h" },
    .{ .base_dir = cmark_zig_prefix, .name = "cmark_export.h" },
};

const common_sources = [_][]const u8{
    cmark_src_prefix ++ "cmark.c",
    cmark_src_prefix ++ "node.c",
    cmark_src_prefix ++ "iterator.c",
    cmark_src_prefix ++ "blocks.c",
    cmark_src_prefix ++ "inlines.c",
    cmark_src_prefix ++ "scanners.c",
    cmark_src_prefix ++ "utf8.c",
    cmark_src_prefix ++ "buffer.c",
    cmark_src_prefix ++ "references.c",
    cmark_src_prefix ++ "render.c",
    cmark_src_prefix ++ "man.c",
    cmark_src_prefix ++ "xml.c",
    cmark_src_prefix ++ "html.c",
    cmark_src_prefix ++ "commonmark.c",
    cmark_src_prefix ++ "latex.c",
    cmark_src_prefix ++ "houdini_href_e.c",
    cmark_src_prefix ++ "houdini_html_e.c",
    cmark_src_prefix ++ "houdini_html_u.c",
    cmark_src_prefix ++ "cmark_ctype.c",
};
