{inputs, ...}: {
  imports = [inputs.flake-parts.flakeModules.easyOverlay];

  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit (pkgs) callPackage lib darwin hostPlatform;
    darwinPkgs = {
      inherit (darwin.apple_sdk.frameworks) Foundation;
    };
  in {
    overlayAttrs = self'.packages;
    packages =
      {
        ldc = callPackage ./ldc {};

        dub = callPackage ./dub {};
      }
      // lib.optionalAttrs hostPlatform.isx86 {
        dmd = callPackage ./dmd darwinPkgs;
      };
  };
}
