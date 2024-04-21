{ self, lib, ... }:
{
  flake.lib = {
    build-status = import ./build-status.nix { inherit lib; };
    dc = import ./dc.nix { inherit lib; };
    inherit (import ./mk-gh-actions-matrix.nix { inherit self lib; }) allowedToFailMap;
    versionUtils = import ./version-utils.nix { };
  };
}
