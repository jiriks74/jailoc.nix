# jailoc and its private VM runtime. Only jailoc is exported. The runtime is
# passed explicitly so callPackage never resolves nixpkgs' libkrun/libkrunfw by
# name; to use a nixpkgs package instead, delete its binding and its inherits.
# Not for libkrun: consumers assert `libkrun ? init`, so a replacement needs jailoc's patches and init.
pkgs: let
  libkrunfw = pkgs.callPackage ./libkrunfw/package.nix {};
  libkrun = pkgs.callPackage ./libkrun/package.nix {inherit libkrunfw;};
  go-microvm-runner = pkgs.callPackage ./go-microvm-runner/package.nix {inherit libkrun libkrunfw;};
in {
  jailoc = pkgs.callPackage ./jailoc/package.nix {inherit go-microvm-runner libkrun libkrunfw;};
}
