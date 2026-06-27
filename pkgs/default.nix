{ inputs, lib, ... }:
let
  inherit (lib) optionalAttrs;
in
{
  imports = [ inputs.flake-parts.flakeModules.easyOverlay ];

  perSystem =
    { self', pkgs, ... }:
    let
      inherit (import ../lib/version-catalog.nix { inherit lib pkgs self'; }) genPkgVersions;
    in
    {
      overlayAttrs = self'.packages;
      legacyPackages =
        { }
        // (genPkgVersions "dmd").hierarchical
        // (genPkgVersions "ldc").hierarchical
        // (genPkgVersions "dub").hierarchical
        // (genPkgVersions "dcd").hierarchical
        // (genPkgVersions "dfix").hierarchical
        // (genPkgVersions "dscanner").hierarchical;

      packages =
        {
          # NOTE: This is only the default. The bootstrap compiler in the
          # version catalog will override this.
          ldc-bootstrap = self'.packages."ldc-binary-1_42_0";
          ldc = self'.packages."ldc-1_42_0";

          # DUB is released alongside DMD. When DMD 2.112.0 shipped, upstream
          # appears to have forgotten to bump DUB from 1.42.0-beta.1 to the
          # final 1.42.0 tag, so the newest released DUB is still this beta.
          # Switch to "dub-1_42_0" once upstream tags the stable release.
          dub = self'.packages."dub-1_42_0-beta_1";

          # dlang-community developer tools (built via nixpkgs' buildDubPackage).
          dcd = self'.packages."dcd-0_16_2";
          dfix = self'.packages."dfix-0_3_5";
          dscanner = self'.packages."dscanner-0_15_2";
        }
        // (genPkgVersions "ldc").flattened "binary"
        // (genPkgVersions "ldc").flattened "source"
        // (genPkgVersions "dub").flattened "source"
        // (genPkgVersions "dcd").flattened "source"
        // (genPkgVersions "dfix").flattened "source"
        // (genPkgVersions "dscanner").flattened "source"
        // optionalAttrs pkgs.hostPlatform.isx86 (
          {
            dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
            dmd = self'.packages."dmd-2_112_0";
          }
          // (genPkgVersions "dmd").flattened "binary"
          // (genPkgVersions "dmd").flattened "source"
        );
    };
}
