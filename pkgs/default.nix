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
  in rec {
    overlayAttrs = self'.packages;
    legacyPackages =
      rec {
        buildDubPackageLDC = pkgs.callPackage ./build-dub-package {
          dub = self'.packages.dub;
          dCompiler = self'.packages.ldc;
        };
        buildDubPackageDMD = pkgs.callPackage ./build-dub-package {
          dub = self'.packages.dub;
          dCompiler = self'.packages.dmd;
        };
        buildDubPackage = buildDubPackageLDC;
      }
      // (genPkgVersions "dmd").hierarchical
      // (genPkgVersions "ldc").hierarchical
      // (genPkgVersions "dub").hierarchical;

    packages =
      optionalAttrs pkgs.stdenv.isLinux rec {
        dscanner = pkgs.callPackage ./dscanner {
          inherit (legacyPackages) buildDubPackage;
        };
        dcd = pkgs.callPackage ./dcd {
          buildDubPackage = legacyPackages.buildDubPackageDMD;
        };
        serve-d = pkgs.callPackage ./serve-d {
          buildDubPackage = legacyPackages.buildDubPackageDMD;
        };
        dlangide = pkgs.callPackage ./dlangide {
          inherit (legacyPackages) buildDubPackage;
        };
      }
      // optionalAttrs pkgs.stdenv.isLinux (import ../examples/dub-pkgs {
        inherit self' pkgs;
        inherit (legacyPackages) buildDubPackage;
      })
      // rec {
        ldc-binary = self'.packages."ldc-binary-1_38_0";
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
