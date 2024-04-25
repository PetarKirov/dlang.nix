{
  lib,
  stdenv,
  dub,
  dmd,
  ldc,
  makeSetupHook,
  jq,
  bash,
  gnugrep,
  fetchgit,
  writeScript,
}: {
  name ? "${args.pname}-${args.version}",
  src ? null,
  sourceRoot ? null,
  prePatch ? "",
  patches ? [],
  postPatch ? "",
  nativeBuildInputs ? [],
  buildInputs ? [],
  # Flags to pass to all dub commands.
  dubFlags ? [],
  # Flags to pass to `dub test`.
  dubTestFlags ? [],
  # Flags to pass to `dub build`.
  dubBuildFlags ? [],
  # Extra files to copy to $out`.
  extraFiles ? [],
  # Dub selection file.
  dubSelections ? "/notexist/dub.selections.json",
  ...
} @ args: let
  inherit (import ../../lib/build-status.nix {inherit lib;}) getBuildStatus;
  dubConfigHook =
    makeSetupHook
    {
      name = "dub-config-hook";
      substitutions = {
        "jq" = "${jq}/bin/jq";
        "shell" = "${bash}/bin/bash";
        "dub" = "${dub}/bin/dub";
      };
    }
    (writeScript "dub-config-hook.sh" ''
      #!@shell@
      echo "Executing dubConfigHook"

      echo "Configuring dub"

      export HOME="/build"
      mkdir -p $HOME/.dub
      if ${gnugrep}/bin/grep "dependenc" ${src}/dub.* &> /dev/null; then
        if [ -f ${src}/dub.selections.json ]; then
            echo "dub.selections.json exists"
        else
            if [ -f "${dubSelections}" ]; then
                echo "Using ${dubSelections}"
            else
                echo "dub.selections.json does not exist. Please supply it manually"
                exit 1
            fi
        fi
        ${
        let
          selectionsJson =
            if builtins.pathExists "${src}/dub.selections.json"
            then "${src}/dub.selections.json"
            else if dubSelections != "/notexist/dub.selections.json"
            then dubSelections
            else null;
          selections =
            if selectionsJson != null
            then (builtins.fromJSON (builtins.readFile selectionsJson)).versions
            else null;
          deps =
            if selections != null
            then
              lib.mapAttrsToList (dep: ver: let
                data = import ../dub/pkgs/${dep}/default.nix;
                pkg = rec {
                  name = dep;
                  version = ver;
                  path = fetchgit {
                    url = data.url;
                    rev = data.versions.${ver}.rev;
                    sha256 = data.versions.${ver}.sha256;
                    fetchSubmodules = false;
                  };
                };
              in
                pkg)
              selections
            else null;

          str =
            if deps != null
            then
              (lib.concatMapStringsSep "\n" (dep: ''
                  dep_path="$HOME/.dub/packages/${dep.name}-${dep.version}"
                  mkdir -p "$dep_path"
                  cp -r "${dep.path}"/* "$dep_path"
                  @dub@ add-local "$dep_path" "${dep.version}"
                '')
                deps)
            else "";
        in
          str
      }
      fi

      echo "Finished dubConfigHook"
    '');

  dubBuildHook =
    makeSetupHook
    {
      name = "dub-build-hook";
      substitutions = {
        "dub" = "${dub}/bin/dub";
        "dmd" = "${dmd}/bin/dmd";
        "ldc" = "${ldc}/bin/ldc";
      };
    }
    ./dub-build-hook.sh;

  dubTestHook =
    makeSetupHook
    {
      name = "dub-test-hook";
      substitutions = {
        "dub" = "${dub}/bin/dub";
        "dmd" = "${dmd}/bin/dmd";
        "ldc" = "${ldc}/bin/ldc";
      };
    }
    ./dub-test-hook.sh;

  dubInstallHook =
    makeSetupHook
    {
      name = "dub-install-hook";
    }
    ./dub-install-hook.sh;
in
  stdenv.mkDerivation (args
    // {
      nativeBuildInputs = nativeBuildInputs ++ [dub ldc dmd dubConfigHook dubBuildHook dubInstallHook dubTestHook];
      buildInputs = buildInputs ++ [dub ldc dmd];

      strictDeps = true;

      meta = (args.meta or {}) // {platforms = args.meta.platforms or dub.meta.platforms;};
      passthru =
        {
          buildStatus = getBuildStatus args.pname args.version stdenv.system;
        }
        // (args.passthru or {});
    })
