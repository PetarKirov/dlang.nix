{
  inputs,
  lib,
  ...
}: let
  inherit (builtins) attrNames listToAttrs map mapAttrs;
  inherit (lib) nameValuePair pipe optionalAttrs;
in {
  imports = [inputs.flake-parts.flakeModules.easyOverlay];

  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit (pkgs) callPackage hostPlatform;
    darwinPkgs = {
      inherit (pkgs.darwin.apple_sdk.frameworks) Foundation;
    };

    genPkgVersions = pkgName: let
      mod = ./. + "/${pkgName}/supported-versions.nix";
      inherit
        (import mod)
        supportedVersions
        getSourceVersion
        getBinaryVersion
        ;
      getVersion = type:
        if type == "source"
        then getSourceVersion
        else getBinaryVersion;
    in {
      flattened = type: let
        nameSuffix =
          if type == "binary"
          then "-binary"
          else "";
      in
        pipe (attrNames supportedVersions."${type}") [
          (
            map (
              version:
                nameValuePair
                "${pkgName}${nameSuffix}-${version}"
                (callPackage (getVersion type version) darwinPkgs)
            )
          )
          listToAttrs
        ];

      hierarchical = {
        "${pkgName}" = pipe ["source" "binary"] [
          (map (type:
            nameValuePair type (
              mapAttrs
              (version: _: (callPackage (getVersion type version) darwinPkgs))
              supportedVersions."${type}"
            )))
          listToAttrs
        ];
      };
    };
  in {
    overlayAttrs = self'.packages;
    legacyPackages =
      {}
      // (genPkgVersions "dmd").hierarchical;
    packages =
      {
        ldc-binary = callPackage ./ldc/bootstrap.nix {};
        ldc = callPackage ./ldc {};

        dub = callPackage ./dub {};
      }
      // optionalAttrs hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2.098.0";
          dmd = self'.packages."dmd-2.100.2";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      );
  };
}
