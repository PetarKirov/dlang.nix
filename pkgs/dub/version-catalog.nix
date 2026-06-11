lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);
  };

  getBinaryVersion = null; # unsupported

  getSourceVersion =
    ourPkgs: version:
    assert builtins.hasAttr version supportedVersions.source;
    let
      componentHashes = supportedVersions.source."${version}";
      package = import ./default.nix (
        {
          inherit version;
          dubSha256 = componentHashes.dub;
        }
        // lib.optionalAttrs (componentHashes ? rev) { inherit (componentHashes) rev; }
      );
    in
    lib.mirrorFunctionArgs package (
      nixpkgs:
      package nixpkgs
      // {
        ${if componentHashes ? d-compiler then "dCompiler" else null} =
          ourPkgs.${componentHashes.d-compiler};
      }
    );
}
