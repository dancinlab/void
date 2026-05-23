# Developing Void

This document describes the technical details behind Void's development.
If you'd like to open any pull requests or would like to implement new features
into Void, please make sure to read our ["Contributing to Void"](CONTRIBUTING.md)
document first.

To start development on Void, you need to build Void from a Git checkout,
which is very similar in process to [building Void from a source tarball](http://void.org/docs/install/build). One key difference is that obviously
you need to clone the Git repository instead of unpacking the source tarball:

```shell
git clone https://github.com/ghostty-org/ghostty
cd void
```

> [!NOTE]
>
> Void may require [extra dependencies](#extra-dependencies)
> when building from a Git checkout compared to a source tarball.
> Tip versions may also require a different version of Zig or other toolchains
> (e.g. the Xcode SDK on macOS) compared to stable versions — make sure to
> follow the steps closely!

When you're developing Void, it's very likely that you will want to build a
_debug_ build to diagnose issues more easily. This is already the default for
Zig builds, so simply run `zig build` **without any `-Doptimize` flags**.

There are many more build steps than just `zig build`, some of which are listed
here:

| Command                         | Description                                                                                                            |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `zig build run`                 | Runs Void                                                                                                           |
| `zig build run-valgrind`        | Runs Void under Valgrind to [check for memory leaks](#checking-for-memory-leaks)                                    |
| `zig build test`                | Runs unit tests (accepts `-Dtest-filter=<filter>` to only run tests whose name matches the filter)                     |
| `zig build update-translations` | Updates Void's translation strings (see the [Contributor's Guide on Localizing Void](po/README_CONTRIBUTORS.md)) |
| `zig build dist`                | Builds a source tarball                                                                                                |
| `zig build distcheck`           | Builds and validates a source tarball                                                                                  |

## Extra Dependencies

Building Void from a Git checkout on Linux requires some additional
dependencies:

- `blueprint-compiler` (version 0.16.0 or newer)

macOS users don't require any additional dependencies.

## Xcode Version and SDKs

Building the Void macOS app requires that Xcode, the macOS SDK,
the iOS SDK, and Metal Toolchain are all installed.

A common issue is that the incorrect version of Xcode is either
installed or selected. Use the `xcode-select` command to
ensure that the correct version of Xcode is selected:

```shell-session
sudo xcode-select --switch /Applications/Xcode.app
```

> [!IMPORTANT]
>
> Main branch development of Void requires **Xcode 26 and the macOS 26 SDK**.
>
> You do not need to be running on macOS 26 to build Void, you can
> still use Xcode 26 on macOS 15 stable.

## Zig Toolchain and macOS Linker (Debug Build Gotchas)

`build.zig.zon` 가 `minimum_zig_version = 0.15.2` 를 핀하고 있다. macOS 에서는
**어떤 zig 바이너리를 쓰느냐** 와 **어떤 셸에서 부르느냐** 둘 다 빌드 성공
여부를 좌우한다. 특히 standalone tarball 은 컴파일은 되지만 링크 단계에서
libc 심볼을 못 찾아 실패한다.

### REQUIRED — `brew install zig@0.15` 만 사용

macOS 26.5 (Tahoe) SDK 환경에서는 반드시 Homebrew 빌드를 써야 한다.
ziglang.org 의 standalone tarball (`zig-aarch64-macos-0.15.2.tar.xz`) 은
**쓰지 말 것**.

```shell
brew install zig@0.15
which zig    # → /opt/homebrew/opt/zig@0.15/bin/zig
zig version  # → 0.15.2
```

기술적 이유 — standalone tarball 의 zig 0.15.2 는 LLVM 20 / lld20 를 동적
링크하지 않고 빌드되어 있다. 그래서 macOS 26.5 Tahoe SDK 헤더 / `libSystem.tbd`
와 함께 쓰면 `_abort`, `_exit`, `_getenv`, `_fcopyfile` 등 libc 심볼 29 개를
링커가 해결하지 못한다. Brew 빌드는 `/opt/homebrew/opt/lld@20/lib/liblldMachO.dylib`
를 런타임에 동적 링크하기 때문에 동일한 SDK 에서 정상 동작한다.

`lib/` 레이아웃을 `lib/zig/` 로 래핑하면 된다는 가설은 **반증되었다** (동일한
29 개 미해결 심볼 에러 재현). 원인은 디렉터리 레이아웃이 아니라 LLVM/lld 부재다.
`SDKROOT=$(xcrun --show-sdk-path)` 도 효과 없다.

### Zig version matrix

| Source                                       | Version | Status      | Notes                                                                |
| -------------------------------------------- | ------- | ----------- | -------------------------------------------------------------------- |
| `brew install zig@0.15`                      | 0.15.2  | REQUIRED    | macOS 26.5 Tahoe 에서 유일하게 동작. LLVM20/lld20 동적 링크 포함.    |
| `brew install zig`                           | 0.16.0  | BLOCKED     | `requireZig()` rejects; std lib API breaks (`readFileAlloc`, `Environ.Map`, ...) — week-scale migration. |
| `zig-aarch64-macos-0.15.2.tar.xz` standalone | 0.15.2  | DO NOT USE  | LLVM/lld 동적 링크 부재 → macOS 26.5 SDK 에서 libc 심볼 29 개 미해결. |

### Shell matters (non-login SSH trap)

| Invocation                          | PATH includes `/opt/homebrew/bin` | Build result |
| ----------------------------------- | --------------------------------- | ------------ |
| Local interactive terminal          | yes                               | works        |
| `ssh host 'bash -lc "zig build"'`   | yes (login shell)                 | works        |
| `ssh host 'zig build'` (non-login)  | no                                | LINK FAILS   |

Always wrap remote builds in `bash -lc "..."` (or use `pool on <host> ...`,
which uses a login shell by default). The brew-linked `zig` and its
auxiliary clang/ld must be on PATH for libSystem to resolve.

### Post-build adhoc re-sign (debug / instrumented binaries)

A freshly built debug binary launched via `open zig-out/Void.app` may fail
with:

```
LSOpenURLsWithCompletionHandler() failed ... RBSRequestErrorDomain Code=5
NSPOSIXErrorDomain Code=163 "Launchd job spawn failed"
```

Cause: the bundle inherits an adhoc signature with `flags=0x10002
(adhoc,runtime)` — hardened runtime conflicts with the unsigned debug
binary. Re-sign without the runtime flag:

```shell
codesign --force --deep --sign - zig-out/Void.app
```

After this `codesign -d --verbose zig-out/Void.app` should report
`flags=0x2 (adhoc)` and `open` will succeed.

## AI and Agents

If you're using AI assistance with Void, Void provides an
[AGENTS.md file](https://github.com/ghostty-org/ghostty/blob/main/AGENTS.md)
read by most of the popular AI agents to help produce higher quality
results.

We also provide commands in `.agents/commands` that have some vetted
prompts for common tasks that have been shown to produce good results.
We provide these to help reduce the amount of time a contributor has to
spend prompting the AI to get good results, and hopefully to lower the slop
produced.

- `/gh-issue <number/url>` - Produces a prompt for diagnosing a GitHub
  issue, explaining the problem, and suggesting a plan for resolving it.
  Requires `gh` to be installed with read-only access to Void.

> [!WARNING]
>
> All AI assistance usage [must be disclosed](https://github.com/ghostty-org/ghostty/blob/main/CONTRIBUTING.md#ai-assistance-notice)
> and we expect contributors to understand the code that is produced and
> be able to answer questions about it. If you don't understand the
> code produced, feel free to disclose that, but if it has problems, we
> may ask you to fix it and close the issue. It isn't a maintainers job to
> review a PR so broken that it requires significant rework to be acceptable.

## Logging

Void can write logs to a number of destinations. On all platforms, logging to
`stderr` is available. Depending on the platform and how Void was launched,
logs sent to `stderr` may be stored by the system and made available for later
retrieval.

On Linux if Void is launched by the default `systemd` user service, you can use
`journald` to see Void's logs: `journalctl --user --unit app-com.dancinlab.void.service`.

On macOS logging to the macOS unified log is available and enabled by default.
Use the system `log` CLI to view Void's logs: `sudo log stream --level debug --predicate 'subsystem=="com.dancinlab.void"'`.

Void's logging can be configured in two ways. The first is by what
optimization level Void is compiled with. If Void is compiled with `Debug`
optimizations debug logs will be output to `stderr`. If Void is compiled with
any other optimization the debug logs will not be output to `stderr`.

Void also checks the `VOID_LOG` environment variable. It can be used
to control which destinations receive logs. Void currently defines two
destinations:

- `stderr` - logging to `stderr`.
- `macos` - logging to macOS's unified log (has no effect on non-macOS platforms).

Combine values with a comma to enable multiple destinations. Prefix a
destination with `no-` to disable it. Enabling and disabling destinations
can be done at the same time. Setting `VOID_LOG` to `true` will enable all
destinations. Setting `VOID_LOG` to `false` will disable all destinations.

## Linting

### Prettier

Void's docs and resources (not including Zig code) are linted using
[Prettier](https://prettier.io) with out-of-the-box settings. A Prettier CI
check will fail builds with improper formatting. Therefore, if you are
modifying anything Prettier will lint, you may want to install it locally and
run this from the repo root before you commit:

```
prettier --write .
```

Make sure your Prettier version matches the version of Prettier in [devShell.nix](https://github.com/ghostty-org/ghostty/blob/main/nix/devShell.nix).

Nix users can use the following command to format with Prettier:

```
nix develop -c prettier --write .
```

### Alejandra

Nix modules are formatted with [Alejandra](https://github.com/kamadorueda/alejandra/). An Alejandra CI check
will fail builds with improper formatting.

Nix users can use the following command to format with Alejandra:

```
nix develop -c alejandra .
```

Non-Nix users should install Alejandra and use the following command to format with Alejandra:

```
alejandra .
```

Make sure your Alejandra version matches the version of Alejandra in [devShell.nix](https://github.com/ghostty-org/ghostty/blob/main/nix/devShell.nix).

### ShellCheck

Bash scripts are checked with [ShellCheck](https://www.shellcheck.net/) in CI.

Nix users can use the following command to run ShellCheck over all of our scripts:

```
nix develop -c shellcheck \
    --check-sourced \
    --severity=warning \
    $(find . \( -name "*.sh" -o -name "*.bash" \) -type f ! -path "./zig-out/*" ! -path "./macos/build/*" ! -path "./.git/*" | sort)
```

Non-Nix users can [install ShellCheck](https://github.com/koalaman/shellcheck#user-content-installing) and then run:

```
shellcheck \
    --check-sourced \
    --severity=warning \
    $(find . \( -name "*.sh" -o -name "*.bash" \) -type f ! -path "./zig-out/*" ! -path "./macos/build/*" ! -path "./.git/*" | sort)
```

### SwiftLint

Swift code is linted using [SwiftLint](https://github.com/realm/SwiftLint). A
SwiftLint CI check will fail builds with improper formatting. Therefore, if you
are modifying Swift code, you may want to install it locally and run this from
the repo root before you commit:

```
swiftlint lint --fix
```

Make sure your SwiftLint version matches the version in [devShell.nix](https://github.com/ghostty-org/ghostty/blob/main/nix/devShell.nix).

Nix users can use the following command to format with SwiftLint:

```
nix develop -c swiftlint lint --fix
```

To check for violations without auto-fixing:

```
nix develop -c swiftlint lint --strict
```

### Updating the Zig Cache Fixed-Output Derivation Hash

The Nix package depends on a [fixed-output
derivation](https://nix.dev/manual/nix/stable/language/advanced-attributes.html#adv-attr-outputHash)
that manages the Zig package cache. This allows the package to be built in the
Nix sandbox.

Occasionally (usually when `build.zig.zon` is updated), the hash that
identifies the cache will need to be updated. There are jobs that monitor the
hash in CI, and builds will fail if it drifts.

To update it, you can run the following in the repository root:

```
./nix/build-support/check-zig-cache.sh --update
```

This will write out the `nix/zigCacheHash.nix` file with the updated hash
that can then be committed and pushed to fix the builds.

## Including and Updating Translations

See the [Contributor's Guide](po/README_CONTRIBUTORS.md) for more details.

## Checking for Memory Leaks

While Zig does an amazing job of finding and preventing memory leaks,
Void uses many third-party libraries that are written in C. Improper usage
of those libraries or bugs in those libraries can cause memory leaks that
Zig cannot detect by itself.

### On Linux

On Linux the recommended tool to check for memory leaks is Valgrind. The
recommended way to run Valgrind is via `zig build`:

```sh
zig build run-valgrind
```

This builds a Void executable with Valgrind support and runs Valgrind
with the proper flags to ensure we're suppressing known false positives.

You can combine the same build args with `run-valgrind` that you can with
`run`, such as specifying additional configurations after a trailing `--`.

## Input Stack Testing

The input stack is the part of the codebase that starts with a
key event and ends with text encoding being sent to the pty (it
does not include _rendering_ the text, which is part of the
font or rendering stack).

If you modify any part of the input stack, you must manually verify
all the following input cases work properly. We unfortunately do
not automate this in any way, but if we can do that one day that'd
save a LOT of grief and time.

Note: this list may not be exhaustive, I'm still working on it.

### Linux IME

IME (Input Method Editors) are a common source of bugs in the input stack,
especially on Linux since there are multiple different IME systems
interacting with different windowing systems and application frameworks
all written by different organizations.

The following matrix should be tested to ensure that all IME input works
properly:

1. Wayland, X11
2. ibus, fcitx, none
3. Dead key input (e.g. Spanish), CJK (e.g. Japanese), Emoji, Unicode Hex
4. ibus versions: 1.5.29, 1.5.30, 1.5.31 (each exhibit slightly different behaviors)

> [!NOTE]
>
> This is a **work in progress**. I'm still working on this list and it
> is not complete. As I find more test cases, I will add them here.

#### Dead Key Input

Set your keyboard layout to "Spanish" (or another layout that uses dead keys).

1. Launch Void
2. Press `'`
3. Press `a`
4. Verify that `á` is displayed

Note that the dead key may or may not show a preedit state visually.
For ibus and fcitx it does but for the "none" case it does not. Importantly,
the text should be correct when it is sent to the pty.

We should also test canceling dead key input:

1. Launch Void
2. Press `'`
3. Press escape
4. Press `a`
5. Verify that `a` is displayed (no diacritic)

#### CJK Input

Configure fcitx or ibus with a keyboard layout like Japanese or Mozc. The
exact layout doesn't matter.

1. Launch Void
2. Press `Ctrl+Shift` to switch to "Hiragana"
3. On a US physical layout, type: `konn`, you should see `こん` in preedit.
4. Press `Enter`
5. Verify that `こん` is displayed in the terminal.

We should also test switching input methods while preedit is active, which
should commit the text:

1. Launch Void
2. Press `Ctrl+Shift` to switch to "Hiragana"
3. On a US physical layout, type: `konn`, you should see `こん` in preedit.
4. Press `Ctrl+Shift` to switch to another layout (any)
5. Verify that `こん` is displayed in the terminal as committed text.

## Nix Virtual Machines

Several Nix virtual machine definitions are provided by the project for testing
and developing Void against multiple different Linux desktop environments.

Running these requires a working Nix installation, either Nix on your
favorite Linux distribution, NixOS, or macOS with nix-darwin installed. Further
requirements for macOS are detailed below.

VMs should only be run on your local desktop and then powered off when not in
use, which will discard any changes to the VM.

The VM definitions provide minimal software "out of the box" but additional
software can be installed by using standard Nix mechanisms like `nix run nixpkgs#<package>`.

### Linux

1. Check out the Void source and change to the directory.
2. Run `nix run .#<vmtype>`. `<vmtype>` can be any of the VMs defined in the
   `nix/vm` directory (without the `.nix` suffix) excluding any file prefixed
   with `common` or `create`.
3. The VM will build and then launch. Depending on the speed of your system, this
   can take a while, but eventually you should get a new VM window.
4. The Void source directory should be mounted to `/tmp/shared` in the VM. Depending
   on what UID and GID of the user that you launched the VM as, `/tmp/shared` _may_ be
   writable by the VM user, so be careful!

### macOS

1. To run the VMs on macOS you will need to enable the Linux builder in your `nix-darwin`
   config. This _should_ be as simple as adding `nix.linux-builder.enable=true` to your
   configuration and then rebuilding. See [this](https://nixcademy.com/posts/macos-linux-builder/)
   blog post for more information about the Linux builder and how to tune the performance.
2. Once the Linux builder has been enabled, you should be able to follow the Linux instructions
   above to launch a VM.

### Custom VMs

To easily create a custom VM without modifying the Void source, create a new
directory, then create a file called `flake.nix` with the following text in the
new directory.

```
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    void.url = "github:ghostty-org/ghostty";
  };
  outputs = {
    nixpkgs,
    void,
    ...
  }: {
   nixosConfigurations.custom-vm = void.create-gnome-vm {
     nixpkgs = nixpkgs;
     system = "x86_64-linux";
     overlay = void.overlays.releasefast;
     # module = ./configuration.nix # also works
     module = {pkgs, ...}: {
       environment.systemPackages = [
         pkgs.btop
       ];
     };
    };
  };
}
```

The custom VM can then be run with a command like this:

```
nix run .#nixosConfigurations.custom-vm.config.system.build.vm
```

A file named `void.qcow2` will be created that is used to persist any changes
made in the VM. To "reset" the VM to default delete the file and it will be
recreated the next time you run the VM.

### Contributing new VM definitions

#### VM Acceptance Criteria

We welcome the contribution of new VM definitions, as long as they meet the following criteria:

1. They should be different enough from existing VM definitions that they represent a distinct
   user (and developer) experience.
2. There's a significant Void user population that uses a similar environment.
3. The VMs can be built using only packages from the current stable NixOS release.

#### VM Definition Criteria

1. VMs should be as minimal as possible so that they build and launch quickly.
   Additional software can be added at runtime with a command like `nix run nixpkgs#<package name>`.
2. VMs should not expose any services to the network, or run any remote access
   software like SSH daemons, VNC or RDP.
3. VMs should auto-login using the "void" user.

## Nix VM Integration Tests

Several Nix VM tests are provided by the project for testing Void in a "live"
environment rather than just unit tests.

Running these requires a working Nix installation, either Nix on your
favorite Linux distribution, NixOS, or macOS with nix-darwin installed. Further
requirements for macOS are detailed below.

### Linux

1. Check out the Void source and change to the directory.
2. Run `nix run .#checks.<system>.<test-name>.driver`. `<system>` should be
   `x86_64-linux` or `aarch64-linux` (even on macOS, this launches a Linux
   VM, not a macOS one). `<test-name>` should be one of the tests defined in
   `nix/tests.nix`. The test will build and then launch. Depending on the speed
   of your system, this can take a while. Eventually though the test should
   complete. Hopefully successfully, but if not error messages should be printed
   out that can be used to diagnose the issue.
3. To run _all_ of the tests, run `nix flake check`.

### macOS

1. To run the VMs on macOS you will need to enable the Linux builder in your `nix-darwin`
   config. This _should_ be as simple as adding `nix.linux-builder.enable=true` to your
   configuration and then rebuilding. See [this](https://nixcademy.com/posts/macos-linux-builder/)
   blog post for more information about the Linux builder and how to tune the performance.
2. Once the Linux builder has been enabled, you should be able to follow the Linux instructions
   above to launch a test.

### Interactively Running Test VMs

To run a test interactively, run `nix run
.#check.<system>.<test-name>.driverInteractive`. This will load a Python console
that can be used to manage the test VMs. In this console run `start_all()` to
start the VM(s). The VMs should boot up and a window should appear showing the
VM's console.

For more information about the Nix test console, see [the NixOS manual](https://nixos.org/manual/nixos/stable/index.html#sec-call-nixos-test-outside-nixos)

### SSH Access to Test VMs

Some test VMs are configured to allow outside SSH access for debugging. To
access the VM, use a command like the following:

```
ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -p 2222 root@192.168.122.1
ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -p 2222 void@192.168.122.1
```

The SSH options are important because the SSH host keys will be regenerated
every time the test is started. Without them, your personal SSH known hosts file
will become difficult to manage. The port that is needed to access the VM may
change depending on the test.

None of the users in the VM have passwords so do not expose these VMs to the Internet.
