{
  inputs,
  lib,
  ...
}: let
  inherit (lib) optionalAttrs;
in {
  imports = [inputs.flake-parts.flakeModules.easyOverlay];

  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit (pkgs) callPackage hostPlatform;

    inherit
      (import ../lib/version-catalog.nix {inherit lib pkgs;})
      genPkgVersions
      ;
  in {
    overlayAttrs = self'.packages;
    legacyPackages =
      {}
      // (genPkgVersions "dmd").hierarchical
      // (genPkgVersions "dub").hierarchical;

    packages =
      {
        ldc-binary = callPackage ./ldc/bootstrap.nix {};
        ldc = callPackage ./ldc {};

        dub = self'.packages."dub-1_30_0";
      }
      // (genPkgVersions "dub").flattened "source"
      // optionalAttrs hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
          dmd = self'.packages."dmd-2_100_2";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      );
  };
}
