const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get version from git describe
    const git_describe = b.run(&.{ "git", "describe", "--tags", "--always" });
    const version = if (git_describe.len > 0)
        std.mem.trimRight(u8, git_describe, "\n\r")
    else
        "0.0.0-dev";

    // Build options for version
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // Fetch dependencies
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // Build libyaml from source
    const yaml_dep = b.dependency("yaml", .{});
    const yaml_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "yaml",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Generate config.h from cmake template
    const config_h = b.addConfigHeader(
        .{ .style = .{ .cmake = yaml_dep.path("cmake/config.h.in") } },
        .{
            .YAML_VERSION_MAJOR = 0,
            .YAML_VERSION_MINOR = 2,
            .YAML_VERSION_PATCH = 5,
            .YAML_VERSION_STRING = "0.2.5",
        },
    );
    yaml_lib.addConfigHeader(config_h);

    yaml_lib.addCSourceFiles(.{
        .root = yaml_dep.path("."),
        .files = &.{
            "src/api.c",
            "src/dumper.c",
            "src/emitter.c",
            "src/loader.c",
            "src/parser.c",
            "src/reader.c",
            "src/scanner.c",
            "src/writer.c",
        },
        .flags = &.{
            "-DYAML_DECLARE_STATIC",
            "-DHAVE_CONFIG_H",
        },
    });
    yaml_lib.addIncludePath(yaml_dep.path("include"));
    yaml_lib.addIncludePath(yaml_dep.path("src"));

    // Main executable
    const exe = b.addExecutable(.{
        .name = "fizz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    exe.root_module.addImport("clap", clap.module("clap"));
    exe.linkLibrary(yaml_lib);
    exe.addIncludePath(yaml_dep.path("include"));

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run fizz");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addOptions("build_options", options);
    unit_tests.root_module.addImport("clap", clap.module("clap"));
    unit_tests.linkLibrary(yaml_lib);
    unit_tests.addIncludePath(yaml_dep.path("include"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
