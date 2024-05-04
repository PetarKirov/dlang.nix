{ lib, ... }:
{
  getBuildStatus =
    package: version: system:
    let
      data = import ./../pkgs/${package}/build-status.nix { inherit lib; };
    in
    data.${version}.${system} or {
      # If not build status is found, we assume that the package builds
      # successfully with no workarounds.
      build = true;
      check = true;
      skippedTests = [ ];
    };
}
