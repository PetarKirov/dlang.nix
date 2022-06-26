{callPackage}:
callPackage ./binary.nix {
  version = "1.28.0";
  hashes = {
    # Get these from `nix-prefetch-url https://github.com/ldc-developers/ldc/releases/download/v1.28.0/ldc2-1.28.0-osx-x86_64.tar.xz` etc..
    osx-x86_64 = "16nhp0k3yrrxzz19d52q8qap8x5lydnrq61vv1fqp34qvq3jaiq2";
    linux-x86_64 = "0y02znkw95jkmkjhgvddmsdhghp42p0rki2hi8qdsagx9mnc71lp";
    linux-aarch64 = "0rbljgbz27cm3zvri6d79a16afqbhl1g4wn3x8501pgzlzckcfpp";
  };
}
