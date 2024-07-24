{
  lib,
  pkgs,
  self',
  ...
}:
let
  inherit (builtins)
    attrNames
    listToAttrs
    map
    mapAttrs
    ;
  inherit (lib) nameValuePair pipe optional;

  inherit (pkgs) callPackage;

  callWithExtras = package:
    let
      result' = callPackage package {
        hostDCompiler = result'.hostDCompiler or self'.packages.ldc-bootstrap;
        inherit (pkgs.darwin.apple_sdk.frameworks) Foundation;
      };
    in result';

  system = pkgs.hostPlatform.system;
  filterBySystem = pkgs: lib.filterAttrs (_name: pkg: builtins.elem system pkg.meta.platforms) pkgs;
in
{
  genPkgVersions =
    pkgName:
    let
      mod = ../pkgs/${pkgName}/version-catalog.nix;
      inherit (import mod lib) supportedVersions getSourceVersion getBinaryVersion;

      supportedTypes =
        (optional (getBinaryVersion != null) "binary") ++ (optional (getSourceVersion != null) "source");

      sanitizeVersion = version: builtins.replaceStrings [ "." ] [ "_" ] version;

      getVersion = type: if type == "source" then getSourceVersion self'.packages else getBinaryVersion self'.packages;
    in
    {
      flattened =
        type:
        let
          nameSuffix = if type == "binary" then "-binary" else "";
        in
        pipe (attrNames supportedVersions."${type}") [
          (map (
            version:
            nameValuePair "${pkgName}${nameSuffix}-${sanitizeVersion version}" (
              callWithExtras (getVersion type version)
            )
          ))
          listToAttrs
          filterBySystem
        ];

      hierarchical = {
        "${pkgName}" = pipe supportedTypes [
          (map (
            type:
            nameValuePair type (
              mapAttrs (version: _: callWithExtras (getVersion type version)) supportedVersions."${type}"
            )
          ))
          listToAttrs
          filterBySystem
        ];
      };
    };
}
