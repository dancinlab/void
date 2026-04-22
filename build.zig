const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const buildpkg = @import("src/build/main.zig");

/// App version from build.zig.zon.
const app_zon_version = @import("build.zig.zon").version;

/// Libvoid version. We use a separate version from the app.
const lib_version = "0.1.0-dev";

/// Minimum required zig version.
const minimum_zig_version = @import("build.zig.zon").minimum_zig_version;

comptime {
    buildpkg.requireZig(minimum_zig_version);
}

pub fn build(b: *std.Build) !void {
    // This defines all the available build options (e.g. `-D`). If you
    // want to know what options are available, you can run `--help` or
    // you can read `src/build/Config.zig`.

    // If we have a VERSION file (present in source tarballs) then we
    // use that as the version source of truth. Otherwise we fall back
    // to what is in the build.zig.zon.
    const file_version: ?[]const u8 = if (b.build_root.handle.readFileAlloc(
        b.allocator,
        "VERSION",
        128,
    )) |content| std.mem.trim(
        u8,
        content,
        &std.ascii.whitespace,
    ) else |_| null;

    const config = try buildpkg.Config.init(
        b,
        file_version orelse app_zon_version,
        lib_version,
    );
    const test_filters = b.option(
        [][]const u8,
        "test-filter",
        "Filter for test. Only applies to Zig tests.",
    ) orelse &[0][]const u8{};

    // Void dependencies used by many artifacts.
    const deps = try buildpkg.SharedDeps.init(b, &config);

    // The modules exported for Zig consumers of libvoid. If you're
    // writing a Zig program that uses libvoid, read this file.
    const mod = try buildpkg.VoidZig.init(
        b,
        &config,
        &deps,
    );

    // All our steps which we'll hook up later. The steps are shown
    // up here just so that they are more self-documenting.
    const run_step = b.step("run", "Run the app");
    const run_valgrind_step = b.step(
        "run-valgrind",
        "Run the app under valgrind",
    );
    const test_step = b.step("test", "Run tests");
    const test_lib_vt_step = b.step(
        "test-lib-vt",
        "Run libvoid-vt tests",
    );
    const test_valgrind_step = b.step(
        "test-valgrind",
        "Run tests under valgrind",
    );
    const translations_step = b.step(
        "update-translations",
        "Update translation files",
    );

    // Void resources like terminfo, shell integration, themes, etc.
    const resources = try buildpkg.VoidResources.init(b, &config, &deps);
    const i18n = if (config.i18n) try buildpkg.VoidI18n.init(b, &config) else null;

    // Void executable, the actual runnable Void program.
    const exe = try buildpkg.VoidExe.init(b, &config, &deps);

    // Void docs
    const docs = try buildpkg.VoidDocs.init(b, &deps);
    if (config.emit_docs) {
        docs.install();
    } else if (config.target.result.os.tag.isDarwin()) {
        // If we aren't emitting docs we need to emit a placeholder so
        // our macOS xcodeproject builds since it expects the `share/man`
        // directory to exist to copy into the app bundle.
        docs.installDummy(b.getInstallStep());
    }

    // Void webdata
    const webdata = try buildpkg.VoidWebdata.init(b, &deps);
    if (config.emit_webdata) webdata.install();

    // Void bench tools
    const bench = try buildpkg.VoidBench.init(b, &deps);
    if (config.emit_bench) bench.install();

    // Void dist tarball
    const dist = try buildpkg.VoidDist.init(b, &config);
    {
        const step = b.step("dist", "Build the dist tarball");
        step.dependOn(dist.install_step);
        const check_step = b.step("distcheck", "Install and validate the dist tarball");
        check_step.dependOn(dist.check_step);
        check_step.dependOn(dist.install_step);
    }

    // libvoid-vt
    const libvoid_vt_shared = shared: {
        if (config.target.result.cpu.arch.isWasm()) {
            break :shared try buildpkg.VoidLibVt.initWasm(
                b,
                &mod,
            );
        }

        break :shared try buildpkg.VoidLibVt.initShared(
            b,
            &mod,
        );
    };
    libvoid_vt_shared.install(b.getInstallStep());

    // libvoid-vt static lib
    const libvoid_vt_static = try buildpkg.VoidLibVt.initStatic(
        b,
        &mod,
    );
    if (config.is_dep) {
        // If we're a dependency, we need to install everything as-is
        // so that dep.artifact("void-vt-static") works.
        libvoid_vt_static.install(b.getInstallStep());
    } else {
        // If we're not a dependency, we rename the static lib to
        // be idiomatic. On Windows, we use a distinct name to avoid
        // colliding with the DLL import library (void-vt.lib).
        const static_lib_name = if (config.target.result.os.tag == .windows)
            "void-vt-static.lib"
        else
            "libvoid-vt.a";
        b.getInstallStep().dependOn(&b.addInstallLibFile(
            libvoid_vt_static.output,
            static_lib_name,
        ).step);
    }

    // libvoid-vt xcframework (Apple only, universal binary).
    // Only when building on macOS (not cross-compiling) since
    // xcodebuild is required.
    if (builtin.os.tag.isDarwin() and config.target.result.os.tag.isDarwin()) {
        const apple_libs = try buildpkg.VoidLibVt.initStaticAppleUniversal(
            b,
            &config,
            &deps,
            &mod,
        );
        const xcframework = buildpkg.VoidLibVt.xcframework(&apple_libs, b);
        b.getInstallStep().dependOn(xcframework.step);
    }

    // Helpgen
    if (config.emit_helpgen) deps.help_strings.install();

    // Runtime "none" is libvoid, anything else is an executable.
    if (config.app_runtime != .none) {
        if (config.emit_exe) {
            exe.install();
            resources.install();
            if (i18n) |v| v.install();
        }
    } else if (!config.emit_lib_vt) {
        // The macOS Void Library
        //
        // This is NOT libvoid (even though its named that for historical
        // reasons). It is just the glue between Void GUI on macOS and
        // the full Void GUI core.
        const lib_shared = try buildpkg.VoidLib.initShared(b, &deps);
        const lib_static = try buildpkg.VoidLib.initStatic(b, &deps);

        // We shouldn't have this guard but we don't currently
        // build on macOS this way ironically so we need to fix that.
        if (!config.target.result.os.tag.isDarwin()) {
            lib_shared.installHeader(); // Only need one header
            if (config.target.result.os.tag == .windows) {
                lib_shared.install("void-internal.dll");
                lib_static.install("void-internal-static.lib");
            } else {
                lib_shared.install("void-internal.so");
                lib_static.install("void-internal.a");
            }
        }
    }

    // macOS only artifacts. These will error if they're initialized for
    // other targets.
    if (config.target.result.os.tag.isDarwin() and
        (config.emit_xcframework or config.emit_macos_app))
    {
        // Void xcframework
        const xcframework = try buildpkg.VoidXCFramework.init(
            b,
            &deps,
            config.xcframework_target,
        );
        if (config.emit_xcframework) {
            xcframework.install();

            // The xcframework build always installs resources because our
            // macOS xcode project contains references to them.
            resources.install();
            if (i18n) |v| v.install();
        }

        // Void macOS app
        const macos_app = try buildpkg.VoidXcodebuild.init(
            b,
            &config,
            .{
                .xcframework = &xcframework,
                .docs = &docs,
                .i18n = if (i18n) |v| &v else null,
                .resources = &resources,
            },
        );
        if (config.emit_macos_app) {
            macos_app.install();
        }
    }

    // Run step
    run: {
        if (config.app_runtime != .none) {
            const run_cmd = b.addRunArtifact(exe.exe);
            if (b.args) |args| run_cmd.addArgs(args);

            // Set the proper resources dir so things like shell integration
            // work correctly. If we're running `zig build run` in Void,
            // this also ensures it overwrites the release one with our debug
            // build.
            run_cmd.setEnvironmentVariable(
                "VOID_RESOURCES_DIR",
                b.getInstallPath(.prefix, "share/void"),
            );

            run_step.dependOn(&run_cmd.step);
            break :run;
        }

        assert(config.app_runtime == .none);

        // On macOS we can run the macOS app. For "run" we always force
        // a native-only build so that we can run as quickly as possible.
        if (config.target.result.os.tag.isDarwin() and
            (config.emit_xcframework or config.emit_macos_app))
        {
            const xcframework_native = try buildpkg.VoidXCFramework.init(
                b,
                &deps,
                .native,
            );
            const macos_app_native_only = try buildpkg.VoidXcodebuild.init(
                b,
                &config,
                .{
                    .xcframework = &xcframework_native,
                    .docs = &docs,
                    .i18n = if (i18n) |v| &v else null,
                    .resources = &resources,
                },
            );

            // Run uses the native macOS app
            run_step.dependOn(&macos_app_native_only.open.step);

            // If we have no test filters, install the tests too
            if (test_filters.len == 0) {
                macos_app_native_only.addTestStepDependencies(test_step);
            }
        }
    }

    // Valgrind
    if (config.app_runtime != .none) {
        // We need to rebuild Void with a baseline CPU target.
        const valgrind_exe = exe: {
            var valgrind_config = config;
            valgrind_config.target = valgrind_config.baselineTarget();
            break :exe try buildpkg.VoidExe.init(
                b,
                &valgrind_config,
                &deps,
            );
        };

        const run_cmd = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        run_cmd.addArtifactArg(valgrind_exe.exe);
        if (b.args) |args| run_cmd.addArgs(args);
        run_valgrind_step.dependOn(&run_cmd.step);
    }

    // Zig module tests
    {
        const mod_vt_test = b.addTest(.{
            .root_module = mod.vt,
            .filters = test_filters,
        });
        const mod_vt_test_run = b.addRunArtifact(mod_vt_test);
        test_lib_vt_step.dependOn(&mod_vt_test_run.step);

        const mod_vt_c_test = b.addTest(.{
            .root_module = mod.vt_c,
            .filters = test_filters,
        });
        const mod_vt_c_test_run = b.addRunArtifact(mod_vt_c_test);
        test_lib_vt_step.dependOn(&mod_vt_c_test_run.step);
    }

    // Tests (skip when building libvoid-vt)
    if (!config.emit_lib_vt) {
        // Full unit tests
        const test_exe = b.addTest(.{
            .name = "void-test",
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = config.baselineTarget(),
                .optimize = .Debug,
                .strip = false,
                .omit_frame_pointer = false,
                .unwind_tables = .sync,
            }),
            // Crash on x86_64 without this
            .use_llvm = true,
        });
        if (config.emit_test_exe) b.installArtifact(test_exe);
        _ = try deps.add(test_exe);

        // Verify our internal libvoid header.
        const void_h = b.addTranslateC(.{
            .root_source_file = b.path("include/void.h"),
            .target = config.baselineTarget(),
            .optimize = .Debug,
        });
        test_exe.root_module.addImport("void.h", void_h.createModule());

        // Normal test running
        const test_run = b.addRunArtifact(test_exe);
        test_step.dependOn(&test_run.step);

        // Normal tests always test our libvoid modules
        //test_step.dependOn(test_lib_vt_step);

        // Valgrind test running
        const valgrind_run = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        valgrind_run.addArtifactArg(test_exe);
        test_valgrind_step.dependOn(&valgrind_run.step);
    }

    // update-translations does what it sounds like and updates the "pot"
    // files. These should be committed to the repo.
    if (i18n) |v| {
        translations_step.dependOn(v.update_step);
    } else {
        try translations_step.addError("cannot update translations when i18n is disabled", .{});
    }
}
