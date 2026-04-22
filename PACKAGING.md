# Packaging Void for Distribution

Void relies on downstream package maintainers to distribute Void to
end-users. This document provides guidance to package maintainers on how to
package Void for distribution.

> [!IMPORTANT]
>
> This document is only accurate for the Void source alongside it.
> **Do not use this document for older or newer versions of Void!** If
> you are reading this document in a different version of Void, please
> find the `PACKAGING.md` file alongside that version.

## Source Tarballs

Source tarballs with stable checksums are available for tagged releases
at `release.files.void.org` in the following URL format where
`VERSION` is the version number with no prefix such as `1.0.0`:

```
https://release.files.void.org/VERSION/void-VERSION.tar.gz
https://release.files.void.org/VERSION/void-VERSION.tar.gz.minisig
```

Signature files are signed with
[minisign](https://jedisct1.github.io/minisign/)
using the following public key:

```
RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV
```

**Tip source tarballs** are available on the
[GitHub releases page](https://github.com/ghostty-org/ghostty/releases/tag/tip).
Use the `void-source.tar.gz` asset and _not the GitHub auto-generated
source tarball_. These tarballs are generated for every commit to
the `main` branch and are not associated with a specific version.

> [!WARNING]
>
> Source tarballs are _not the same_ as a Git checkout. Source tarballs
> contain some preprocessed files that allow building Void with less
> dependencies. If you are building Void from a Git checkout, the
> steps below are the same but they may require additional dependencies
> not listed here. See the `README.md` for more information on building
> from a Git checkout.
>
> For everyone except Void developers, please use the source tarballs.
> We generate tip source tarballs for users following the development
> branch.

## Zig Version

[Zig](https://ziglang.org) is required to build Void. Prior to Zig 1.0,
Zig releases often have breaking changes. Void requires specific Zig versions
depending on the Void version in order to build. To make things easier for
package maintainers, Void always uses some _released_ version of Zig.

To find the version of Zig required to build Void, check the `required_zig`
constant in `build.zig`. You don't need to know Zig to extract this information.
This version will always be an official released version of Zig.

For example, at the time of writing this document, Void requires Zig 0.14.0.

## Building Void

The following is a standard example of how to build Void _for system
packages_. This is not the recommended way to build Void for your
own system. For that, see the primary README.

1. First, we fetch our dependencies from the internet into a cached directory.
   This is the only step that requires internet access:

```sh
ZIG_GLOBAL_CACHE_DIR=/tmp/offline-cache ./nix/build-support/fetch-zig-cache.sh
```

2. Next, we build Void. This step requires no internet access:

```sh
DESTDIR=/tmp/void \
zig build \
  --prefix /usr \
  --system /tmp/offline-cache/p \
  -Doptimize=ReleaseFast \
  -Dcpu=baseline
```

The build options are covered in the next section, but this will build
and install Void to `/tmp/void` with the prefix `/usr` (i.e. the
binary will be at `/tmp/void/usr/bin/void`). This style is common
for system packages which separate a build and install step, since the
install step can then be done with a `mv` or `cp` command (from `/tmp/void`
to wherever the package manager expects it).

### Build Options

Void uses the Zig build system. You can see all available build options by
running `zig build --help`. The following are options that are particularly
relevant to package maintainers:

- `--prefix`: The installation prefix. Combine with the `DESTDIR` environment
  variable to install to a temporary directory for packaging.

- `--system`: The path to the offline cache directory. This disables
  any package fetching from the internet. This flag also triggers all
  dependencies to be dynamically linked by default. This flag also makes
  the binary a PIE (Position Independent Executable) by default (override
  with `-Dpie`).

- `-Doptimize=ReleaseFast`: Build with optimizations enabled and safety checks
  disabled. This is the recommended build mode for distribution. I'd prefer
  a safe build but terminal emulators are performance-sensitive and the
  safe build is currently too slow. I plan to improve this in the future.
  Other build modes are available: `Debug`, `ReleaseSafe`, and `ReleaseSmall`.

- `-Dcpu=baseline`: Build for the "baseline" CPU of the target architecture.
  This avoids building for newer CPU features that may not be available on
  all target machines.

- `-Dtarget=$arch-$os-$abi`: Build for a specific target triple. This is
  often necessary for system packages to specify a specific minimum Linux
  version, glibc, etc. Run `zig targets` to a get a full list of available
  targets.
