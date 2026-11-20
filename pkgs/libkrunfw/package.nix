{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  flex,
  bison,
  bc,
  cpio,
  perl,
  python3,
  elfutils,
}: let
  kernelVersion = "6.12.109";
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "libkrunfw";
    version = "5.6.2";

    src = fetchFromGitHub {
      owner = "libkrun";
      repo = "libkrunfw";
      tag = "v${finalAttrs.version}";
      hash = "sha256-HklZgZPjXe+eAGzRulEwRR1eo83tGlZBTRooCv0/ADU=";
    };

    # Same attribute name as nixpkgs, so the updater can use --custom-dep kernelSrc.
    kernelSrc = fetchurl {
      url = "mirror://kernel/linux/kernel/v6.x/linux-${kernelVersion}.tar.xz";
      hash = "sha256-VITlUqM04VAZ9K66ieW1jwRlHPL04k4E3p8VLxw44/o=";
    };

    __structuredAttrs = true;

    postPatch = ''
      # Builds have no network; the preceding Makefile command creates tarballs/.
      substituteInPlace Makefile \
        --replace-fail 'curl $(KERNEL_REMOTE) -o $(KERNEL_TARBALL)' 'ln -s ${finalAttrs.kernelSrc} $(KERNEL_TARBALL)'
    '';

    nativeBuildInputs = [
      flex
      bison
      bc
      cpio
      perl
      (python3.withPackages (p: [p.pyelftools]))
    ];

    buildInputs = [elfutils];

    makeFlags = [
      "PREFIX=${placeholder "out"}"
    ];

    # Fixes https://github.com/containers/libkrunfw/issues/55.
    env = lib.optionalAttrs stdenv.hostPlatform.isAarch64 {
      NIX_CFLAGS_COMPILE = "-march=armv8-a+crypto";
    };

    enableParallelBuilding = true;

    postFixup = ''
      # Linux ELF checks: fixup has moved the upstream lib64 directory to lib.
      test -e "$out/lib/libkrunfw.so.5"
      readelf -d "$out/lib/libkrunfw.so.5" | grep -q 'SONAME.*libkrunfw.so.5'
      test "$(grep -caF "Linux version ${kernelVersion}" "$out/lib/libkrunfw.so.5")" -ge 1
    '';

    meta = {
      description = "Dynamic library bundling the guest payload consumed by libkrun";
      homepage = "https://github.com/libkrun/libkrunfw";
      license = with lib.licenses; [lgpl21Only gpl2Only];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  })
