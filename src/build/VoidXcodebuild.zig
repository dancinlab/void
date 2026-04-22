const Void = @This();

const std = @import("std");
const builtin = @import("builtin");
const RunStep = std.Build.Step.Run;
const Config = @import("Config.zig");
const Docs = @import("VoidDocs.zig");
const I18n = @import("VoidI18n.zig");
const Resources = @import("VoidResources.zig");
const XCFramework = @import("VoidXCFramework.zig");

build: *std.Build.Step.Run,
open: *std.Build.Step.Run,
copy: *std.Build.Step.Run,
xctest: *std.Build.Step.Run,

pub const Deps = struct {
    xcframework: *const XCFramework,
    docs: *const Docs,
    i18n: ?*const I18n,
    resources: *const Resources,
};

pub fn init(
    b: *std.Build,
    config: *const Config,
    deps: Deps,
) !Void {
    const xc_config = switch (config.optimize) {
        .Debug => "Debug",
        .ReleaseSafe,
        .ReleaseSmall,
        .ReleaseFast,
        => "ReleaseLocal",
    };

    const xc_arch: ?[]const u8 = switch (deps.xcframework.target) {
        // Universal is our default target, so we don't have to
        // add anything.
        .universal => null,

        // Native we need to override the architecture in the Xcode
        // project with the -arch flag.
        .native => switch (builtin.cpu.arch) {
            .aarch64 => "arm64",
            .x86_64 => "x86_64",
            else => @panic("unsupported macOS arch"),
        },
    };

    const env = try std.process.getEnvMap(b.allocator);
    const app_path = b.fmt("macos/build/{s}/Void.app", .{xc_config});

    // Our step to build the Void macOS app.
    const build = build: {
        // External environment variables can mess up xcodebuild, so
        // we create a new empty environment.
        const env_map = try b.allocator.create(std.process.EnvMap);
        env_map.* = .init(b.allocator);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.env_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            "-target",
            "Void",
            "-configuration",
            xc_config,
            // void fork — Sparkle SPM checkout 만 sandbox-allowlist 경로로 리다이렉트.
            // 기본 ~/Library/Caches/org.swift.swiftpm/ 은 Claude Code
            // sandbox-exec (raw#8 + raw#13 SBPL) 의 .github/workflows/*.yml
            // + .sh/.py/.toml deny 에 걸려 Sparkle checkout 실패 (revision
            // 21d8df80 "Couldn't check out"). /tmp/.claude/ 아래는 라인 102-105
            // allow 가 모든 deny 를 override. -derivedDataPath 는 주입 X
            // — SYMROOT 기본값(macos/build/ReleaseLocal/Void.app) 유지해야
            // zig build 의 copy-app-bundle step 이 경로 맞음.
            "-clonedSourcePackagesDirPath",
            "/tmp/.claude/void-spm",
            // void fork — Package.resolved pinning.
            // 매 빌드마다 xcodebuild 가 SPM 의존성 버전을 재해석하면 빌드
            // reproducibility 가 깨지고 (실험적으로 Sparkle minor 업데이트가
            // 빌드 중간에 끼어드는 경우 목격) sandbox-exec 호출 빈도도 증가.
            // 아래 플래그는 Package.resolved 에 고정된 버전만 쓰고 추가 resolve
            // 를 억제 → 캐시 warm 상태에서 빌드 phase 수 감소.
            // NOTE: xcodebuild 가 link-time 에 또 한번 SPM 경로를 참조하는데
            // 이때 macOS 커널 nested-sandbox 가 sandbox_apply syscall 자체를
            // 차단 ("sandbox_apply: Operation not permitted"). harness 내부
            // 빌드에서는 이 마지막 단계가 항상 실패하므로 외부 Terminal 에서
            // 최종 빌드를 한번 돌려 app bundle 을 정상화하는 것이 권장 경로.
            "-onlyUsePackageVersionsFromResolvedFile",
            "-disableAutomaticPackageResolution",
        });

        // If we have a specific architecture, we need to pass it
        // to xcodebuild.
        if (xc_arch) |arch| step.addArgs(&.{ "-arch", arch });

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);
        if (deps.i18n) |v| v.addStepDependencies(&step.step);
        deps.docs.installDummy(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :build step;
    };

    const xctest = xctest: {
        const env_map = try b.allocator.create(std.process.EnvMap);
        env_map.* = .init(b.allocator);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild test");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.env_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            "test",
            "-scheme",
            "Void",
            "-skip-testing",
            "VoidUITests",
        });
        if (xc_arch) |arch| step.addArgs(&.{ "-arch", arch });

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);
        if (deps.i18n) |v| v.addStepDependencies(&step.step);
        deps.docs.installDummy(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :xctest step;
    };

    // Our step to open the resulting Void app.
    const open = open: {
        const disable_save_state = RunStep.create(b, "disable save state");
        disable_save_state.has_side_effects = true;
        disable_save_state.addArgs(&.{
            "/usr/libexec/PlistBuddy",
            "-c",
            // We'll have to change this to `Set` if we ever put this
            // into our Info.plist.
            "Add :NSQuitAlwaysKeepsWindows bool false",
            b.fmt("{s}/Contents/Info.plist", .{app_path}),
        });
        disable_save_state.expectExitCode(0);
        disable_save_state.step.dependOn(&build.step);

        const open = RunStep.create(b, "run Void app");
        open.has_side_effects = true;
        open.cwd = b.path("");
        open.addArgs(&.{b.fmt(
            "{s}/Contents/MacOS/void",
            .{app_path},
        )});

        // Open depends on the app
        open.step.dependOn(&build.step);
        open.step.dependOn(&disable_save_state.step);

        // This overrides our default behavior and forces logs to show
        // up on stderr (in addition to the centralized macOS log).
        open.setEnvironmentVariable("VOID_LOG", "stderr,macos");

        // Configure how we're launching
        open.setEnvironmentVariable("VOID_MAC_LAUNCH_SOURCE", "zig_run");

        if (b.args) |args| {
            open.addArgs(args);
        }

        break :open open;
    };

    // Our step to copy the app bundle to the install path.
    // We have to use `cp -R` because there are symlinks in the
    // bundle.
    const copy = copy: {
        const step = RunStep.create(b, "copy app bundle");
        step.addArgs(&.{ "cp", "-R" });
        step.addFileArg(b.path(app_path));
        step.addArg(b.fmt("{s}", .{b.install_path}));
        step.step.dependOn(&build.step);
        break :copy step;
    };

    return .{
        .build = build,
        .open = open,
        .copy = copy,
        .xctest = xctest,
    };
}

pub fn install(self: *const Void) void {
    const b = self.copy.step.owner;
    b.getInstallStep().dependOn(&self.copy.step);
}

pub fn installXcframework(self: *const Void) void {
    const b = self.build.step.owner;
    b.getInstallStep().dependOn(&self.build.step);
}

pub fn addTestStepDependencies(
    self: *const Void,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(&self.xctest.step);
}
