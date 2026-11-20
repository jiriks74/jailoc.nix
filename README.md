# jailoc-nix

## About

A Nix flake for [jailoc](https://github.com/seznam/jailoc), built together with
its VM runtime from source: the go-microvm runner, libkrun with jailoc's patches
and a static musl guest init, and libkrunfw with its Linux kernel.

## Usage

Run it directly:

```sh
nix run github:jiriks74/jailoc.nix -- --help
```

As a flake input:

```nix
{
  inputs.jailoc.url = "github:jiriks74/jailoc.nix";

  # then, in a module or package set:
  #   inputs.jailoc.packages.${pkgs.stdenv.hostPlatform.system}.jailoc
}
```

Or through the overlay:

```nix
nixpkgs.overlays = [ inputs.jailoc.overlays.default ];
```

The overlay re-exports this flake's build, so you get the nixpkgs revision it
was tested with.

Supported systems: `x86_64-linux` and `aarch64-linux`.

> [!WARNING]
> `inputs.jailoc.inputs.nixpkgs.follows = "nixpkgs"` works, but it rebuilds
> the whole runtime (a Linux kernel included) against your nixpkgs, and it
> needs Go >= 1.26.8. Untested combinations are on you.

## Host requirements

- Read-write access to `/dev/kvm`.
- A kernel with Landlock ABI 2+ (Linux 5.19+).

Both come from the caveats in jailoc's `.goreleaser.yml`. When this flake lags
behind an upstream release, jailoc's update notifier will say so; set
`JAILOC_NO_UPDATE_NOTIFIER=1` to silence it.

## Layout

```
flake.nix                          outputs: packages, overlays.default, checks, formatter
pkgs/default.nix                   wires jailoc and its private runtime together
pkgs/jailoc/package.nix            jailoc, with guards against runtime drift
pkgs/go-microvm-runner/package.nix go-microvm runner at the revision jailoc's go.mod pins
pkgs/libkrun/package.nix           libkrun plus the static guest init (passthru.init)
pkgs/libkrunfw/package.nix         libkrunfw and the kernel it embeds
```

Only `jailoc` is exported. The runtime is passed explicitly in
`pkgs/default.nix`, so `callPackage` never picks up nixpkgs' `libkrun` or
`libkrunfw` by name. To use a nixpkgs package instead, delete its binding there
and the matching `inherit`s. This works for `libkrunfw` and `go-microvm-runner`,
but not for `libkrun`: both consumers assert `libkrun ? init`, which stock
nixpkgs libkrun lacks, so a libkrun replacement must keep jailoc's patches and
the `init` passthru.

## Updating

**jailoc.** Run `nix run nixpkgs#nix-update -- --flake jailoc`, then build. If
the new release moved its runtime pins, the guards fail and name the file to
fix.

**go-microvm.** Take the revision from the `replace` line in jailoc's `go.mod`,
then update `rev`, `hash` and `vendorHash` in
`pkgs/go-microvm-runner/package.nix`. The pin is a branch head of a personal
fork, not a tag, so check the revision by hand.

**libkrun and libkrunfw.** Their versions come from go-microvm's `versions.env`;
the kernel version comes from `KERNEL_VERSION` in libkrunfw's `Makefile`. Update
`version`, `hash` and `cargoDeps.hash` in `pkgs/libkrun/package.nix`, and
`version`, `hash`, `kernelVersion` and the `kernelSrc` hash in
`pkgs/libkrunfw/package.nix`.

**Patches.** libkrun reads them straight from the jailoc source pinned in
`pkgs/libkrun/package.nix`'s `jailocSrc`, so there is nothing to copy. When you
bump jailoc, bump `jailocVersion` and `hash` there to match
`pkgs/jailoc/package.nix`, and update the patch filename list only if the patch
set itself changed upstream.

## Checks

The jailoc build runs:

- jailoc's Go unit tests, the same way upstream CI does;
- a version check of `jailoc --version`;
- a check that the binary embeds the runner path;
- a guard that fails when jailoc's `go.mod` pins a different go-microvm
  revision.

The runner checks go-microvm's `versions.env` against the libkrun and libkrunfw
versions. libkrunfw checks that the built library contains the expected kernel,
and the guest init is checked to be statically linked.

Each runtime component builds on its own:

```sh
nix build .#jailoc.runtime.libkrunfw
nix build .#jailoc.runtime.libkrun
nix build .#jailoc.runtime.init
nix build .#jailoc.runtime.go-microvm-runner
```

> [!NOTE]
> The first build compiles a Linux kernel for libkrunfw, so expect it to
> take a while.

## Roadmap

1. **aarch64-darwin.** jailoc's
   [macOS notes](https://github.com/seznam/jailoc/blob/v2.7.2/docs/development.md#macos)
   list what's needed, in short:
   1. a darwin libkrunfw recipe built from upstream's
      `libkrunfw-prebuilt-aarch64.tgz` release asset;
   2. the guest init cross-built as a static aarch64 Linux binary, and darwin
      wiring;
   3. an offline libkrun build with `fixDarwinDylibNames` and no link-time
      libkrunfw;
   4. a runner without the Homebrew cgo paths, ad-hoc signed with go-microvm's
      entitlements, unstripped, with an `otool -L` linkage check;
   5. a `macos-15` CI build job. CI can only prove the build, signature and
      linkage; booting a VM needs a real Apple Silicon Mac.
2. **Runtime-pin updater.** A `passthru.updateScript` that reads jailoc's
   `go.mod`, go-microvm's `versions.env` and libkrunfw's `Makefile`.
3. **Scheduled update workflow.** It opens a PR for review and is never
   auto-merged.
4. **Binary cache**, optionally, so users don't compile the kernel.
