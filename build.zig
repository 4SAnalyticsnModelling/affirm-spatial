const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addAffirmSpatialExe(b, target, optimize);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run AFFIRM Spatial");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_cmd = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_cmd.step);

    const dist_step = b.step("dist", "Build AFFIRM Spatial executables for supported OS targets");
    for (dist_targets) |dist_target| {
        const dist_exe = addAffirmSpatialExe(b, b.resolveTargetQuery(dist_target.query), .ReleaseFast);
        const install = b.addInstallArtifact(dist_exe, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("dist/{s}", .{dist_target.name}) } },
            .dest_sub_path = dist_target.exe_name,
            .pdb_dir = .disabled,
            .compiler_rt_dyn_lib_dir = .disabled,
        });
        dist_step.dependOn(&install.step);
    }
}

fn addAffirmSpatialExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "affirm_spatial",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/affirm_spatial.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
}

const DistTarget = struct {
    name: []const u8,
    exe_name: []const u8,
    query: std.Target.Query,
};

const dist_targets = [_]DistTarget{
    .{
        .name = "windows-x86_64",
        .exe_name = "affirm_spatial.exe",
        .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    },
    .{
        .name = "windows-aarch64",
        .exe_name = "affirm_spatial.exe",
        .query = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
    },
    .{
        .name = "linux-x86_64",
        .exe_name = "affirm_spatial",
        .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    },
    .{
        .name = "linux-aarch64",
        .exe_name = "affirm_spatial",
        .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    },
    .{
        .name = "macos-x86_64",
        .exe_name = "affirm_spatial",
        .query = .{ .cpu_arch = .x86_64, .os_tag = .macos },
    },
    .{
        .name = "macos-aarch64",
        .exe_name = "affirm_spatial",
        .query = .{ .cpu_arch = .aarch64, .os_tag = .macos },
    },
};
