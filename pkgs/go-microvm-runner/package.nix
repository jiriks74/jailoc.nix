{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pkg-config,
  libkrun,
  libkrunfw,
}:
assert lib.assertMsg (libkrun ? init) "go-microvm-runner needs jailoc's libkrun from pkgs/libkrun, not nixpkgs' libkrun";
  buildGoModule (finalAttrs: {
    pname = "go-microvm-runner";
    # Date of the pinned pseudo-version in jailoc's go.mod.
    version = "0-unstable-2026-11-19";

    src = fetchFromGitHub {
      owner = "thejoeejoee";
      repo = "go-microvm";
      # Head of the jailoc/integration branch of jailoc's fork (go.mod replace line); not a tag.
      rev = "e0fa2a88b1cb7806673c0596e0e9f3f54084a43d";
      hash = "sha256-+HKeh1zETZ2Y6kEMCwpy7BIE5kNWPKonkWOWQBbW5sw=";
    };

    vendorHash = "sha256-zSfWYHdngggVSCU9fRYK7/9ansS0vbe3oBbBPyTKnyo=";

    subPackages = ["runner/cmd/go-microvm-runner"];

    env.CGO_ENABLED = 1;

    nativeBuildInputs = [pkg-config];

    buildInputs = [libkrun];

    # Upstream tests need a hypervisor, unavailable in the build sandbox.
    doCheck = false;

    # go-microvm pins the libkrun/libkrunfw it was tested against; drift here
    # means a silently broken VM runtime. Only version strings are interpolated,
    # so this adds no dependency to the goModules derivation.
    postPatch = ''
      libkrunLine=$(grep -E '^LIBKRUN_VERSION=' versions.env || true)
      if [[ $libkrunLine != "LIBKRUN_VERSION=v${libkrun.version}" ]]; then
        echo "error: go-microvm's versions.env wants '$libkrunLine'; update pkgs/libkrun/package.nix to match" >&2
        exit 1
      fi
      libkrunfwLine=$(grep -E '^LIBKRUNFW_VERSION=' versions.env || true)
      if [[ $libkrunfwLine != "LIBKRUNFW_VERSION=v${libkrunfw.version}" ]]; then
        echo "error: go-microvm's versions.env wants '$libkrunfwLine'; update pkgs/libkrunfw/package.nix to match" >&2
        exit 1
      fi
    '';

    postFixup = ''
      # Linux ELF checks: link to jailoc's patched libkrun and retain its RUNPATH.
      dynamic=$(readelf -d "$out/bin/go-microvm-runner")
      grep -q 'NEEDED.*\[libkrun\.so\.1\]' <<< "$dynamic" || {
        echo "error: go-microvm-runner must list libkrun.so.1 in NEEDED" >&2
        exit 1
      }
      grep 'RUNPATH' <<< "$dynamic" | grep -Fq "${lib.getLib libkrun}/lib" || {
        echo "error: go-microvm-runner RUNPATH must contain ${lib.getLib libkrun}/lib" >&2
        exit 1
      }
    '';

    meta = {
      description = "CGO runner for libkrun micro-VMs, from jailoc's go-microvm fork";
      homepage = "https://github.com/thejoeejoee/go-microvm";
      license = lib.licenses.asl20;
      mainProgram = "go-microvm-runner";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  })
