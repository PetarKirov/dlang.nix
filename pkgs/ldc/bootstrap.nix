{callPackage}:
callPackage ./binary.nix {
  version = "1.28.0";
  hashes = {
    # COMPILER=ldc VERSION='1.28.0' ./scripts/fetch-binary
    "android-aarch64" = "sha256-UmZuvq7d7kAsAiy83Dm4wnBF5vqrFeU8clZLnq8yzP8=";
    "android-armv7a" = "sha256-ybIuqE7Vc4r83xdA9QHupooyab2n4anrHxOfnE5blt4=";
    "freebsd-x86_64" = "sha256-13YsPqfowDM3k7YN0elSroZubcSSSbMx6UDkot9D6oY=";
    "linux-aarch64" = "sha256-9zo22af/3QAK6sNy8gKFCztlgkqnmZj3H5Ud8deTdGU=";
    "linux-x86_64" = "sha256-l4bDbE39Kd0wilDEmcEV5MIHm66t7QflrFOWxKf9Ang=";
    "osx-arm64" = "sha256-+XhrjCjYrx/dMx2OuImt2AKF2+v7l+pH1d2REKffB0s=";
    "osx-x86_64" = "sha256-AkclB96YjItd2DsYnG3ztHR0FUZYlJbC/z1nPya40Jo=";
    "windows-x64" = "sha256-Jrs+znd073DZx0heq1+8GC1OdEEeSo0vM56bQhp28Gk=";
    "windows-x86" = "sha256-r1RlsxbftYLe1P1vg9+gLf3YlvrW05fMU9CY47qfkoE=";
  };
}
