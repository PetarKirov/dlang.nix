{ lib }:
let
  inherit (lib) listToAttrs nameValuePair;

  versions = builtins.attrNames (lib.importJSON ./supported-source-versions.json);

  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  # `dub test` pulls test-only deps not in the lock; keep checks off for now.
  forAll =
    check:
    listToAttrs (
      map (
        version:
        nameValuePair version (
          listToAttrs (
            map (
              system:
              nameValuePair system {
                build = true;
                inherit check;
                skippedTests = [ ];
              }
            ) systems
          )
        )
      ) versions
    );
in
forAll false
