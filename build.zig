const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zigjvm", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkSystemLibrary("c");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Setup tests.
    const test_step = b.step("test", "Test the app");
    {
        const t = b.addTest("src/main.zig");
        t.linkSystemLibrary("c");
        test_step.dependOn(&t.step);
    }
    {
        const t = b.addTest("src/loader.zig");
        t.linkSystemLibrary("c");
        test_step.dependOn(&t.step);
    }
    {
        const t = b.addTest("src/vm.zig");
        t.linkSystemLibrary("c");
        test_step.dependOn(&t.step);
    }

    test_step.dependOn(&b.addTest("src/types.zig").step);

    test_step.dependOn(&b.addTest("src/memo.zig").step);
}
