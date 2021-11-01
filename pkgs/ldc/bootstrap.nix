{callPackage}:
callPackage ./binary.nix {
  version = "1.28.0";
  hashes = {
    # COMPILER=ldc VERSION='1.28.0' ./scripts/fetch-binary
    "linux-x86_64" = "sha256-l4bDbE39Kd0wilDEmcEV5MIHm66t7QflrFOWxKf9Ang=";
    "linux-aarch64" = "sha256-9zo22af/3QAK6sNy8gKFCztlgkqnmZj3H5Ud8deTdGU=";
    "osx-x86_64" = "sha256-AkclB96YjItd2DsYnG3ztHR0FUZYlJbC/z1nPya40Jo=";
    "osx-arm64" = "sha256-+XhrjCjYrx/dMx2OuImt2AKF2+v7l+pH1d2REKffB0s=";
  };
}
