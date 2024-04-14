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
    inherit
      (import ../lib/version-catalog.nix {inherit lib pkgs;})
      genPkgVersions
      ;
  in {
    overlayAttrs = self'.packages;
    legacyPackages =
      {}
      // (genPkgVersions "dmd").hierarchical
      // (genPkgVersions "ldc").hierarchical
      // (genPkgVersions "dub").hierarchical;

    packages =
      rec {
        buildDubPackage = pkgs.callPackage ./build-dub-package {
          dub = self'.packages.dub;
          dmd = self'.packages.dmd;
        };
        dscanner = pkgs.callPackage ./dscanner {
          inherit buildDubPackage;
        };
        serve-d = pkgs.callPackage ./serve-d {
          inherit buildDubPackage;
        };
      }
      // rec {
        ldc-binary = self'.packages."ldc-binary-1_34_0";
        ldc = self'.packages."ldc-1_30_0";

        dub = self'.packages."dub-1_31_0";
      }
      // (genPkgVersions "ldc").flattened "binary"
      // (genPkgVersions "ldc").flattened "source"
      // (genPkgVersions "dub").flattened "source"
      // optionalAttrs pkgs.hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
          dmd = self'.packages."dmd-2_105_2";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      );
  };
}
