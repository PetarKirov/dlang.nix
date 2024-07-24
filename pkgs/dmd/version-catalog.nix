lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);

    binary = builtins.fromJSON (builtins.readFile ./supported-binary-versions.json);
  };

  getSourceVersion =
    ourPkgs: version:
    assert builtins.hasAttr version supportedVersions.source;
    let
      componentHashes = supportedVersions.source."${version}";
      package = import ./generic.nix (
      {
        inherit version;
        dmdSha256 = componentHashes.dmd;
        phobosSha256 = componentHashes.phobos;
        toolsSha256 = componentHashes.tools;
      } // (if componentHashes ? "druntime" then { druntimeSha256 = componentHashes.druntime; } else { }));
    in lib.mirrorFunctionArgs package
      (nixpkgs:
      package nixpkgs // { ${if componentHashes ? host-d-compiler then "hostDCompiler" else null}
        = ourPkgs.${componentHashes.host-d-compiler}; });

  getBinaryVersion =
    pkgs: version:
    assert builtins.hasAttr version supportedVersions.binary;
    let
      componentHashes = supportedVersions.binary."${version}";
    in
    import ./binary.nix {
      inherit version;
      hashes = componentHashes;
    };
}
