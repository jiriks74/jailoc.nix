{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  git,
  cacert,
  coreutils,
  gnused,
  versionCheckHook,
  go-microvm-runner,
  libkrun,
  libkrunfw,
}:
assert lib.assertMsg (libkrun ? init) "jailoc needs jailoc's libkrun from pkgs/libkrun, not nixpkgs' libkrun";
  buildGoModule (finalAttrs: {
    pname = "jailoc";
    version = "2.8.0";

    src = fetchFromGitHub {
      owner = "seznam";
      repo = "jailoc";
      tag = "v${finalAttrs.version}";
      hash = "sha256-Sl4/lz2wFwD2BII38iN8xRHYWB355IFSFYzav2kcHj8=";
    };

    vendorHash = "sha256-qqYH+h1S0nZHGqM1kdk0KI3GPSUnQhdEVK52oO7WWd8=";

    subPackages = ["cmd/jailoc"];

    env.CGO_ENABLED = 0;

    postPatch = ''
      # The VM test harness resets PATH; keep its stubs before the Nix tools.
      substituteInPlace internal/vm/init_test.go \
        --replace-fail 'h.bin + ":/usr/bin:/bin"' 'h.bin + ":${lib.makeBinPath [coreutils gnused]}"'
    '';

    ldflags = [
      "-s"
      "-w"
      # Version without a v, as in jailoc's GoReleaser {{.Version}}.
      "-X main.version=${finalAttrs.version}"
      "-X main.commit=${finalAttrs.src.tag}"
      "-X github.com/seznam/jailoc/internal/cmd.defaultVMRunner=${lib.getExe go-microvm-runner}"
      "-X github.com/seznam/jailoc/internal/cmd.defaultVMLibDir=${lib.makeLibraryPath [libkrun libkrunfw]}"
    ];

    preBuild = ''
      # The runner must come from the go-microvm revision jailoc's go.mod pins.
      replace=$(grep -E '^replace github.com/stacklok/go-microvm ' go.mod || true)
      if [[ ! $replace =~ =\>\ github.com/${go-microvm-runner.src.owner}/${go-microvm-runner.src.repo}\ v[^\ ]*-${builtins.substring 0 12 go-microvm-runner.src.rev}$ ]]; then
        echo "error: go.mod has '$replace', expected ${go-microvm-runner.src.owner}/${go-microvm-runner.src.repo} at ${go-microvm-runner.src.rev}; update pkgs/go-microvm-runner/package.nix" >&2
        exit 1
      fi
      # Embed jailoc-guest for linux/arm64 and linux/amd64, as GoReleaser does.
      go generate ./internal/guestbin
    '';
    # The vendored-modules derivation runs preBuild too, before vendor/ exists.
    overrideModAttrs = _: {preBuild = "";};

    checkPhase = ''
      runHook preCheck
      # Like upstream CI: all packages, without the runtime -X ldflags.
      go test -vet=off $checkFlags ./...
      runHook postCheck
    '';
    preCheck = ''
      export HOME=$(mktemp -d)
    '';
    # Sandbox-only failures, not jailoc bugs:
    # - TestStopSession, TestOpenSharesOneSession: spawn a subprocess with Dir: "/", which
    #   the read-only Nix build sandbox rejects; the passing lifecycle test uses t.TempDir().
    # - TestConfinedRunnerAccess/read_dynamic_loader_cache: /etc/ld.so.cache does not exist
    #   in the Nix sandbox, where binaries resolve libraries via RPATH/RUNPATH.
    # - TestReloadSpecRunningSharesExcludeSnapshots: nixpkgs' cacert ships a Mozilla/NSS-style
    #   bundle with a label line (e.g. "ACCVRAIZ1") before each "-----BEGIN CERTIFICATE-----"
    #   block; jailoc's CA-bundle validator requires each block to start with the PEM header
    #   and rejects the label. A normal host's system bundle (e.g. Debian's
    #   ca-certificates.crt) is a plain concatenation and does not hit this.
    checkFlags = ["-skip=^TestStopSession$|^TestOpenSharesOneSession$|^TestReloadSpecRunningSharesExcludeSnapshots$|^TestConfinedRunnerAccess$/^read_dynamic_loader_cache$"];

    doInstallCheck = true;
    nativeInstallCheckInputs = [versionCheckHook];
    versionCheckProgramArg = "--version";
    postInstallCheck = ''
      grep -qF ${lib.getExe go-microvm-runner} $out/bin/jailoc || { echo "error: jailoc does not embed the runner path" >&2; exit 1; }
    '';

    nativeBuildInputs = [installShellFiles git cacert];

    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      installShellCompletion --cmd jailoc \
        --bash <($out/bin/jailoc completion bash) \
        --fish <($out/bin/jailoc completion fish) \
        --zsh <($out/bin/jailoc completion zsh)
    '';

    passthru.runtime = {
      inherit go-microvm-runner libkrun libkrunfw;
      inherit (libkrun) init;
    };

    meta = {
      description = "Manage sandboxed environments for headless OpenCode coding agents";
      homepage = "https://github.com/seznam/jailoc";
      changelog = "https://github.com/seznam/jailoc/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.mit;
      mainProgram = "jailoc";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  })
