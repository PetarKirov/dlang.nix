lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);
  };

  getBinaryVersion = null; # unsupported

  # Source patches per version, kept out of supported-source-versions.json,
  # which the version tool regenerates.
  patches = {
    # Forwards LDC's -mexec-model= to the link and adds a "wasi" platform.
    "1.43.0-alpha-5efed36" = [ ./patches/dub-wasi-exec-model-and-platform.patch ];
  };

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
        // lib.optionalAttrs (patches ? ${version}) { patches = patches.${version}; }
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
