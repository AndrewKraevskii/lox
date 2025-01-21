const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;

    const is_wasm = target.result.isWasm();
    if (is_wasm) {
        wasmBuild(b, target, optimize);
        return;
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zlox",
        .root_module = exe_mod,
        .use_llvm = false,
        .use_lld = false,
    });

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn wasmBuild(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm_entry.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zlox",
        .root_module = exe_mod,
        // .use_llvm = true,
        // .use_lld = true,
    });

    exe.rdynamic = true;
    exe.entry = .disabled;

    b.installDirectory(.{
        .source_dir = b.path("site/"),
        .install_dir = .bin,
        .install_subdir = "",
    });
    b.installArtifact(exe);
    const run_server_command = b.addSystemCommand(&.{
        "python3",
        "-m",
        "http.server",
        "8080",
        "--directory",
        b.exe_dir,
    });

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_server_command.step);
}
