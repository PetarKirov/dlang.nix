{ callPackage }:
callPackage ./binary.nix {
  version = "2.097.2";
  hashes = {
    # get these from `nix-prefetch-url http://downloads.dlang.org/releases/2.x/2.097.2/dmd.2.097.2.linux.tar.xz` etc..
    osx = "021mwsssgpjsil5sjy47jfclrkq6155bm0gillpcdz7rv1vjnfhw";
    linux = "04ckf54zgclkfdjr2palwiz68bdn7jqiynk37k7njwxc8i4bg066";
  };
}
