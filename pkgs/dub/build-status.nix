{ lib }:
let
  inherit (lib)
    versionAtLeast
    nameValuePair
    listToAttrs
    ;

  versionUtils = import ../../lib/version-utils.nix { };
  inherit (versionUtils) versionBetweenInclusive;

  supportedVersions = builtins.attrNames (lib.importJSON ./supported-source-versions.json);

  latestVersion = versionUtils.latestVersion supportedVersions;

  mergeVersions = attrs: lib.foldl lib.recursiveUpdate { } attrs;

  between =
    start: end: func:
    lib.pipe supportedVersions [
      (builtins.filter (versionBetweenInclusive start end))
      (builtins.map (version: nameValuePair version (func version)))
      listToAttrs
    ];

  baseSkippedTests = [
    "issue502-root-import"
    "issue674-concurrent-dub.sh"
    "issue672-upgrade-optional.sh"
    "issue990-download-optional-selected.sh"
    "issue877-auto-fetch-package-on-run.sh"
    "issue1037-better-dependency-messages.sh"
    "issue1416-maven-repo-pkg-supplier.sh"
    "issue1180-local-cache-broken.sh"
    "issue1574-addcommand.sh"
    "issue1524-maven-upgrade-dependency-tree.sh"
    "issue1773-lint.sh"

    "ddox.sh"
    "fetchzip.sh"
    "feat663-search.sh"
    "git-dependency"
    "interactive-remove.sh"
    "timeout.sh"
    "version-spec.sh"
    "0-init-multi.sh"
    "0-init-multi-json.sh"
    "4-describe-data-1-list.sh"
    "4-describe-data-3-zero-delim.sh"
    "4-describe-import-paths.sh"
    "4-describe-string-import-paths.sh"
    "4-describe-json.sh"
    "5-convert-stdout.sh"
    "issue1003-check-empty-ld-flags.sh"
    "issue103-single-file-package.sh"
    "issue1040-run-with-ver.sh"
    "issue1091-bogus-rebuild.sh"
    "issue1194-warn-wrong-subconfig.sh"
    "issue1277.sh"
    "issue1372-ignore-files-in-hidden-dirs.sh"
    "issue1447-build-settings-vars.sh"
    "issue1531-toolchain-requirements.sh"
    "issue346-redundant-flags.sh"
    "issue361-optional-deps.sh"
    "issue564-invalid-upgrade-dependency.sh"
    "issue586-subpack-dep.sh"
    "issue616-describe-vs-generate-commands.sh"
    "issue686-multiple-march.sh"
    "issue813-fixed-dependency.sh"
    "issue813-pure-sub-dependency.sh"
    "issue820-extra-fields-after-convert.sh"
    "issue923-subpackage-deps.sh"
    "single-file-sdl-default-name.sh"
    "subpackage-common-with-sourcefile-globbing.sh"
    "issue934-path-dep.sh"
    "issue2258-dynLib-exe-dep"
    "1-dynLib-simple"
    "1-exec-simple-package-json"
    "1-exec-simple"
    "1-staticLib-simple"
    "2-dynLib-dep"
    "2-staticLib-dep"
    "2-dynLib-with-staticLib-dep"
    "2-sourceLib-dep/"
    "3-copyFiles"
    "custom-source-main-bug487"
    "custom-unittest"
    "issue1262-version-inheritance-diamond"
    "issue1003-check-empty-ld-flags"
    "ignore-hidden-1"
    "ignore-hidden-2"
    "issue1427-betterC"
    "issue130-unicode-*"
    "issue1262-version-inheritance"
    "issue1372-ignore-files-in-hidden-dirs"
    "issue1350-transitive-none-deps"
    "issue1775"
    "issue1447-build-settings-vars"
    "issue1408-inherit-linker-files"
    "issue1551-var-escaping"
    "issue754-path-selection-fail"
    "issue1788-incomplete-string-import-override"
    "subpackage-ref"
    "issue777-bogus-path-dependency"
    "issue959-path-based-subpack-dep"
    "issue97-targettype-none-nodeps"
    "issue97-targettype-none-onerecipe"
    "path-subpackage-ref"
    "sdl-package-simple"
    "dpath-variable"
  ];

  getSkippedTests =
    version:
    baseSkippedTests
    ++ lib.optionals (versionAtLeast version "1.41.0") [
      "issue2698-cimportpaths-broken-with-dmd-ldc"
      "pr2642-cache-db"
      "pr2644-describe-artifact-path"
      "pr2647-build-deep"
      "use-c-sources"
    ];

  systems = [
    "x86_64-linux"
    "i686-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  makeSystemAttrs =
    version:
    listToAttrs (
      map (
        system:
        nameValuePair system {
          build = true;
          check = true;
          skippedTests = getSkippedTests version;
        }
      ) systems
    );
in
mergeVersions [ (between "1.30.0" latestVersion (version: makeSystemAttrs version)) ]
