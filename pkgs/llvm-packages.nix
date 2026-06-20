# A combined view of the `llvmPackages_*` sets the D compilers build against.
#
# Most LLVM releases come straight from the flake's pinned nixpkgs (passed in
# as e.g. `llvmPackages_18`). Older releases that have since been dropped from
# nixpkgs-unstable are supplied from their own pinned nixpkgs revisions. We
# only ever consume a single `llvmPackages_*` attribute out of each historical
# pin, so they are fetched here rather than threaded through the flake inputs,
# which keeps them out of the main dependency closure and out of flake.lock.
{
  system,
  # LLVM releases still packaged by the flake's nixpkgs are passed through.
  llvmPackages_18,
}:
let
  # Import a historical nixpkgs revision purely to borrow an LLVM release it
  # still packages. `fetchTarball` with a fixed `sha256` is pure, so this stays
  # eval-cacheable even though it is not tracked by flake.lock.
  llvmFromPinnedNixpkgs =
    {
      rev,
      sha256,
      attr,
    }:
    (import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
      inherit sha256;
    }) { inherit system; }).${attr};
in
{
  # LDC <= 1.40 builds against LLVM 12, which was removed from nixpkgs-unstable.
  # Borrow it from the last nixpkgs revision that still shipped it.
  llvmPackages_12 = llvmFromPinnedNixpkgs {
    rev = "b134951a4c9f3c995fd7be05f3243f8ecd65d798";
    sha256 = "0zydsqiaz8qi4zd63zsb2gij2p614cgkcaisnk11wjy3nmiq0x1s";
    attr = "llvmPackages_12";
  };

  # LDC >= 1.41 builds against LLVM 18, still present in the flake's nixpkgs.
  inherit llvmPackages_18;
}
