{callPackage}:
callPackage ./binary.nix {
  version = "2.098.0";
  hashes = {
    # get these from:
    #   nix-prefetch-url http://downloads.dlang.org/releases/2.x/2.098.0/dmd.2.098.0.linux.tar.xz
    #   nix-prefetch-url http://downloads.dlang.org/releases/2.x/2.098.0/dmd.2.098.0.osx.tar.xz
    linux = "0i81vg218n3bbj2s2x6kl6xqdw3vajz74ynpk2vjhy6lkzjya10i";
    osx = "0hpkqwj80ydbmssch9a4gzknnrbmyw37g43ygrj9ljcx8baam03p";
  };
}
