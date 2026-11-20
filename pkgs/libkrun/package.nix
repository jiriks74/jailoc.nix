{
  lib,
  stdenv,
  pkgsStatic,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  pkg-config,
  zstd,
  libkrunfw,
}: let
  # The same jailoc release pkgs/jailoc/package.nix fetches, used only to read its
  # libkrun patches directly - Nix reuses the identical store path, no extra fetch.
  # Keep this version/hash in sync with pkgs/jailoc/package.nix when bumping jailoc.
  jailocVersion = "2.7.2";
  jailocSrc = fetchFromGitHub {
    owner = "seznam";
    repo = "jailoc";
    tag = "v${jailocVersion}";
    hash = "sha256-Zb3cLEyAbu0YGBEgQ3f28KMuDFtNbNy6Mi83+pxztp8=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "libkrun";
    version = "1.19.7";

    src = fetchFromGitHub {
      owner = "libkrun";
      repo = "libkrun";
      tag = "v${finalAttrs.version}";
      hash = "sha256-VtepY0sAqP18OIhIPwESoGi7E2Ahs4ihJjLyLH78JAM=";
    };

    # jailoc's libkrun patches, read directly from the jailoc source above instead
    # of a vendored copy. 0001 is upstream f5fc9f25 and can go once a libkrun
    # release contains it; 0003 only affects macOS.
    patches = map (name: "${jailocSrc}/scripts/vm-runtime/libkrun-patches/${name}") [
      "0001-arch-x86_64-raise-IRQ_MAX-to-23.patch"
      "0002-arch-x86_64-route-all-IOAPIC-pins-in-the-MP-table.patch"
      "0003-virtio-fs-macos-open-unlinked-inodes-nonblocking.patch"
    ];

    outputs = [
      "out"
      "dev"
    ];

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version src;
      hash = "sha256-Ab7b37Npf0vNg7rF8KfPdLYCBuBCyRAYhR13RLecV04=";
    };

    # libkrun dlopens libkrunfw by name: keep it NEEDED so RUNPATH survives stdenv's shrinking fixup.
    env.RUSTFLAGS = toString (
      map (flag: "-C link-arg=" + flag) [
        "-Wl,--push-state,--no-as-needed"
        "-lkrunfw"
        "-Wl,--pop-state"
      ]
    );
    env.KRUN_INIT_BINARY_PATH = "${finalAttrs.passthru.init}/init.krun";

    nativeBuildInputs = [
      rustPlatform.cargoSetupHook
      rustPlatform.bindgenHook
      cargo
      rustc
      pkg-config
    ];

    buildInputs = [libkrunfw] ++ lib.optional stdenv.hostPlatform.isx86_64 zstd;

    makeFlags = [
      "PREFIX=${placeholder "out"}"
      "BLK=1"
      "NET=1"
    ];

    postInstall = ''
      mkdir -p $dev/lib/pkgconfig
      mv $out/lib64/pkgconfig $dev/lib/
      mv $out/include $dev/

      # Upstream writes absolute paths; point them at the final split outputs.
      substituteInPlace "$dev/lib/pkgconfig/libkrun.pc" \
        --replace-fail "libdir=$out/lib64" "libdir=$out/lib" \
        --replace-fail "includedir=$out/include" "includedir=$dev/include"
    '';

    postFixup = ''
      # Linux ELF checks: lib64 normalization and RUNPATH shrinking have finished.
      test -e "$out/lib/libkrun.so.1"
      readelf -d "$out/lib/libkrun.so.1" | grep -q 'NEEDED.*\[libkrunfw\.so\.5\]'
      readelf -d "$out/lib/libkrun.so.1" | grep -q 'SONAME.*\[libkrun\.so\.1\]'
      readelf -d "$out/lib/libkrun.so.1" | grep 'RUNPATH' | grep -Fq '${libkrunfw}/lib'

      test -d "$out/lib"
      test -d "$dev/include"
      grep -Fxq "libdir=$out/lib" "$dev/lib/pkgconfig/libkrun.pc"
      grep -Fxq "includedir=$dev/include" "$dev/lib/pkgconfig/libkrun.pc"
    '';

    passthru = {
      # Exposed for consumers that only hold libkrun; nothing in this repo reads it,
      # they take libkrunfw as a direct argument.
      inherit libkrunfw;

      # The jailoc-side guards use this to detect a stock nixpkgs libkrun, which lacks it.
      # Guest init embedded into libkrun, built against static musl so no glibc code
      # ends up in libkrun; same source and patches as libkrun.
      init = pkgsStatic.stdenv.mkDerivation {
        pname = "libkrun-init";
        inherit (finalAttrs) version src patches;
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          $CC -O2 -static -Wall -o init.krun src/init_blob/init/init.c src/init_blob/init/dhcp.c
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -Dm755 init.krun $out/init.krun
          runHook postInstall
        '';
        postInstall = ''
          if $READELF -l $out/init.krun | grep -q INTERP; then
            echo "error: init.krun is not statically linked" >&2
            exit 1
          fi
        '';
        meta = {
          description = "Statically linked guest init (init.krun) from libkrun";
          homepage = "https://github.com/libkrun/libkrun";
          license = lib.licenses.asl20;
          platforms = lib.platforms.linux;
        };
      };
    };

    meta = {
      description = "Micro-VM library with jailoc's patches and musl guest init";
      homepage = "https://github.com/libkrun/libkrun";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  })
