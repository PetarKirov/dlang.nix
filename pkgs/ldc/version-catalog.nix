lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);

    binary = builtins.fromJSON (builtins.readFile ./supported-binary-versions.json);
  };

  getSourceVersion =
    pkgs: version:
    assert builtins.hasAttr version supportedVersions.source;
    let
      componentHashes = supportedVersions.source."${version}";
    in
    import ./generic.nix {
      inherit version;
      sha256 = componentHashes.src;
      # Optional `llvm-version` field pins a specific LLVM for this LDC version
      # (e.g. "22" for the wasm32-wasip2 fork). Absent => generic.nix's default.
      llvmPackagesOverride =
        if componentHashes ? "llvm-version" then
          pkgs."llvmPackages_${componentHashes."llvm-version"}"
        else
          null;
    };

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
