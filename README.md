<!-- LOGO -->
<h1>
<p align="center">
  <br>void
</h1>
  <p align="center">
    AI-native terminal with first-class grid mode. void-based fork, perf-first.
    <br />
    See <a href="VOID_FORK.md">VOID_FORK.md</a> for fork rationale and direction.
    <br />
    <br />
    <em>— original void README follows below —</em>
    <br /><br />
  </p>
</p>

<!-- LOGO -->
<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Logo" width="128">
  <br>Void
</h1>
  <p align="center">
    Fast, native, feature-rich terminal emulator pushing modern features.
    <br />
    A native GUI or embeddable library via <code>libvoid</code>.
    <br />
    <a href="#about">About</a>
    ·
    <a href="https://void.org/download">Download</a>
    ·
    <a href="https://void.org/docs">Documentation</a>
    ·
    <a href="CONTRIBUTING.md">Contributing</a>
    ·
    <a href="HACKING.md">Developing</a>
  </p>
</p>

## About

Void is a terminal emulator that differentiates itself by being
fast, feature-rich, and native. While there are many excellent terminal
emulators available, they all force you to choose between speed,
features, or native UIs. Void provides all three.

**`libvoid`** is a cross-platform, zero-dependency C and Zig library
for building terminal emulators or utilizing terminal functionality
(such as style parsing). Anyone can use `libvoid` to build a terminal
emulator or embed a terminal into their own applications. See
[Ghostling](https://github.com/ghostty-org/ghostling) for a minimal complete project
example or the [`examples` directory](https://github.com/ghostty-org/ghostty/tree/main/example)
for smaller examples of using `libvoid` in C and Zig.

For more details, see [About Void](https://void.org/docs/about).

## Download

See the [download page](https://void.org/download) on the Void website.

## Documentation

See the [documentation](https://void.org/docs) on the Void website.

## Contributing and Developing

If you have any ideas, issues, etc. regarding Void, or would like to
contribute to Void through pull requests, please check out our
["Contributing to Void"](CONTRIBUTING.md) document. Those who would like
to get involved with Void's development as well should also read the
["Developing Void"](HACKING.md) document for more technical details.

## Roadmap and Status

Void is stable and in use by millions of people and machines daily.

The high-level ambitious plan for the project, in order:

|  #  | Step                                                    | Status |
| :-: | ------------------------------------------------------- | :----: |
|  1  | Standards-compliant terminal emulation                  |   ✅   |
|  2  | Competitive performance                                 |   ✅   |
|  3  | Rich windowing features -- multi-window, tabbing, panes |   ✅   |
|  4  | Native Platform Experiences                             |   ✅   |
|  5  | Cross-platform `libvoid` for Embeddable Terminals    |   ✅   |
|  6  | Void-only Terminal Control Sequences                 |   ❌   |

Additional details for each step in the big roadmap below:

#### Standards-Compliant Terminal Emulation

Void implements all of the regularly used control sequences and
can run every mainstream terminal program without issue. For legacy sequences,
we've done a [comprehensive xterm audit](https://github.com/ghostty-org/ghostty/issues/632)
comparing Void's behavior to xterm and building a set of conformance
test cases.

In addition to legacy sequences (what you'd call real "terminal" emulation),
Void also supports more modern sequences than almost any other terminal
emulator. These features include things like the Kitty graphics protocol,
Kitty image protocol, clipboard sequences, synchronized rendering,
light/dark mode notifications, and many, many more.

We believe Void is one of the most compliant and feature-rich terminal
emulators available.

Terminal behavior is partially a de jure standard
(i.e. [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/))
but mostly a de facto standard as defined by popular terminal emulators
worldwide. Void takes the approach that our behavior is defined by
(1) standards, if available, (2) xterm, if the feature exists, (3)
other popular terminals, in that order. This defines what the Void project
views as a "standard."

#### Competitive Performance

Void is generally in the same performance category as the other highest
performing terminal emulators.

"The same performance category" means that Void is much faster than
traditional or "slow" terminals and is within an unnoticeable margin of the
well-known "fast" terminals. For example, Void and Alacritty are usually within
a few percentage points of each other on various benchmarks, but are both
something like 100x faster than Terminal.app and iTerm. However, Void
is much more feature rich than Alacritty and has a much more native app
experience.

This performance is achieved through high-level architectural decisions and
low-level optimizations. At a high-level, Void has a multi-threaded
architecture with a dedicated read thread, write thread, and render thread
per terminal. Our renderer uses OpenGL on Linux and Metal on macOS.
Our read thread has a heavily optimized terminal parser that leverages
CPU-specific SIMD instructions. Etc.

#### Rich Windowing Features

The Mac and Linux (build with GTK) apps support multi-window, tabbing, and
splits with additional features such as tab renaming, coloring, etc. These
features allow for a higher degree of organization and customization than
single-window terminals.

#### Native Platform Experiences

Void is a cross-platform terminal emulator but we don't aim for a
least-common-denominator experience. There is a large, shared core written
in Zig but we do a lot of platform-native things:

- The macOS app is a true SwiftUI-based application with all the things you
  would expect such as real windowing, menu bars, a settings GUI, etc.
- macOS uses a true Metal renderer with CoreText for font discovery.
- macOS supports AppleScript, Apple Shortcuts (AppIntents), etc.
- The Linux app is built with GTK.
- The Linux app integrates deeply with systemd if available for things
  like always-on, new windows in a single instance, cgroup isolation, etc.

Our goal with Void is for users of whatever platform they run Void
on to think that Void was built for their platform first and maybe even
exclusively. We want Void to feel like a native app on every platform,
for the best definition of "native" on each platform.

#### Cross-platform `libvoid` for Embeddable Terminals

In addition to being a standalone terminal emulator, Void is a
C-compatible library for embedding a fast, feature-rich terminal emulator
in any 3rd party project. This library is called `libvoid`.

Due to the scope of this project, we're breaking libvoid down into
separate libraries, starting with `libvoid-vt`. The goal of
this project is to focus on parsing terminal sequences and maintaining
terminal state. This is covered in more detail in this
[blog post](https://mitchellh.com/writing/libvoid-is-coming).

`libvoid-vt` is already available and usable today for Zig and C and
is compatible for macOS, Linux, Windows, and WebAssembly. The functionality
is extremely stable (since its been proven in Void GUI for a long time),
but the API signatures are still in flux.

`libvoid` is already heavily in use. See [`examples`](https://github.com/ghostty-org/ghostty/tree/main/example)
for small examples of using `libvoid` in C and Zig or the
[Ghostling](https://github.com/ghostty-org/ghostling) project for a
complete example. See [awesome-libvoid](https://github.com/Uzaaft/awesome-libvoid)
for a list of projects and resources related to `libvoid`.

We haven't tagged libvoid with a version yet and we're still working
on a better docs experience, but our [Doxygen website](https://libvoid.tip.void.org/)
is a good resource for the C API.

#### Void-only Terminal Control Sequences

We want and believe that terminal applications can and should be able
to do so much more. We've worked hard to support a wide variety of modern
sequences created by other terminal emulators towards this end, but we also
want to fill the gaps by creating our own sequences.

We've been hesitant to do this up until now because we don't want to create
more fragmentation in the terminal ecosystem by creating sequences that only
work in Void. But, we do want to balance that with the desire to push the
terminal forward with stagnant standards and the slow pace of change in the
terminal ecosystem.

We haven't done any of this yet.

## Crash Reports

Void has a built-in crash reporter that will generate and save crash
reports to disk. The crash reports are saved to the `$XDG_STATE_HOME/void/crash`
directory. If `$XDG_STATE_HOME` is not set, the default is `~/.local/state`.
**Crash reports are _not_ automatically sent anywhere off your machine.**

Crash reports are only generated the next time Void is started after a
crash. If Void crashes and you want to generate a crash report, you must
restart Void at least once. You should see a message in the log that a
crash report was generated.

> [!NOTE]
>
> Use the `void +crash-report` CLI command to get a list of available crash
> reports. A future version of Void will make the contents of the crash
> reports more easily viewable through the CLI and GUI.

Crash reports end in the `.voidcrash` extension. The crash reports are in
[Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/). You can
upload these to your own Sentry account to view their contents, but the format
is also publicly documented so any other available tools can also be used.
The `void +crash-report` CLI command can be used to list any crash reports.
A future version of Void will show you the contents of the crash report
directly in the terminal.

To send the crash report to the Void project, you can use the following
CLI command using the [Sentry CLI](https://docs.sentry.io/cli/installation/):

```shell-session
SENTRY_DSN=https://e914ee84fd895c4fe324afa3e53dac76@o4507352570920960.ingest.us.sentry.io/4507850923638784 sentry-cli send-envelope --raw <path to void crash>
```

> [!WARNING]
>
> The crash report can contain sensitive information. The report doesn't
> purposely contain sensitive information, but it does contain the full
> stack memory of each thread at the time of the crash. This information
> is used to rebuild the stack trace but can also contain sensitive data
> depending on when the crash occurred.
