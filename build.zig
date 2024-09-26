const std = @import("std");
const mach = @import("mach");

const Demo = enum {
    claude,
    rotating,
    camera,
    multiple,
    unknown,
};

const demo = Demo.multiple;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,

        // Since we're only using @import("mach").core, we can specify this to avoid
        // pulling in unneccessary dependencies.
        .core = true,
    });

    // Iterate over the key-value pairs of mach_dep.builder.modules
    // std.debug.print("Modules:\n", .{});
    // var it = mach_dep.builder.modules.iterator();
    // while (it.next()) |entry| {
    //     std.debug.print("  {s}\n", .{entry.key_ptr.*});
    // }

    // include zmath
    const zmath = b.dependency("zmath", .{});

    // switch the demo based on the demo constant
    var src_path: []const u8 = "src/main.zig";
    switch (demo) {
        Demo.claude => src_path = "src/demos/claude_cube/main.zig",
        Demo.rotating => src_path = "src/demos/rotating_cube/main.zig",
        Demo.camera => src_path = "src/demos/camera_cube/main.zig",
        Demo.multiple => src_path = "src/demos/multiple_cubes/main.zig",
        else => {},
    }

    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "ZigVoxel",
        .src = src_path,
        .target = target,
        .optimize = optimize,
        .deps = &[_]std.Build.Module.Import{
            .{
                .name = "zmath",
                .module = zmath.module("root"),
            },
        },
    });
    if (b.args) |args| app.run.addArgs(args);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
