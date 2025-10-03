{ lib }:
let
  inherit (lib)
    versionOlder
    versionAtLeast
    nameValuePair
    listToAttrs
    ;

  versionBetween =
    after: before: version:
    ((builtins.compareVersions version after) >= 0) && ((builtins.compareVersions version before) <= 0);

  supportedVersions = builtins.attrNames (lib.importJSON ./supported-source-versions.json);

  latestVersion = lib.last supportedVersions;

  mergeVersions = attrs: lib.foldl lib.recursiveUpdate { } attrs;

  between =
    start: end: func:
    lib.pipe supportedVersions [
      (builtins.filter (version: versionBetween start end version))
      (builtins.map (version: nameValuePair version (func version)))
      listToAttrs
    ];

  getInfo = version: rec {
    hasDruntimeRepo = versionOlder version "2.101.0";

    dmdTestDir = if hasDruntimeRepo then "dmd/test" else "dmd/compiler/test";

    cxxTestDir =
      if lib.versionAtLeast version "2.092.0" then
        "${dmdTestDir}/runnable_cxx"
      else
        "${dmdTestDir}/runnable";

    skippedTests =
      [
        # Tests that rely on the time of build
        "${dmdTestDir}/compilable/ddocYear.d"

        # GDB tests
        "${dmdTestDir}/runnable/gdb1.d"
        "${dmdTestDir}/runnable/gdb10311.d"
        "${dmdTestDir}/runnable/gdb14225.d"
        "${dmdTestDir}/runnable/gdb14276.d"
        "${dmdTestDir}/runnable/gdb14313.d"
        "${dmdTestDir}/runnable/gdb14330.d"
        "${dmdTestDir}/runnable/gdb15729.sh"
        "${dmdTestDir}/runnable/gdb4149.d"
        "${dmdTestDir}/runnable/gdb4181.d"
      ]
      # tests that rely on objdump whitespace
      ++ (
        if versionAtLeast version "2.087.0" then
          [
            "${dmdTestDir}/runnable/cdvecfill.sh"
            "${dmdTestDir}/compilable/cdcmp.d"
          ]
        else
          [
            "${dmdTestDir}/runnable/test_cdvecfill.d"
            "${dmdTestDir}/runnable/test_cdcmp.d"
          ]
      )

      ++ lib.optionals (versionBetween "2.089.0" "2.092.2" version) [ "${dmdTestDir}/dshell/test6952.d" ]
      # This test is patched on it's current path, but would have to patch
      # the patch to work on the file path before repository unification.
      ++ lib.optionals (hasDruntimeRepo) [ "${dmdTestDir}/fail_compilation/needspkgmod.d" ];

    darwinSkippedTests =
      let
        tests =
          skippedTests
          ++ [
            "${cxxTestDir}/cpp11.d"
            "${cxxTestDir}/cpp_stdlib.d"
            "${cxxTestDir}/cppa.d"
            "${cxxTestDir}/externmangle2.d"
            "${cxxTestDir}/cpp_abi_tests.d"
            "${cxxTestDir}/externmangle.d"
            "${dmdTestDir}/dshell/dll_cxx.d"
          ]
          ++ lib.optionals (versionBetween "2.099.0" latestVersion version) [
            "${cxxTestDir}/test22287.d"
            "${cxxTestDir}/test7925.d"
          ]
          ++ lib.optionals (versionBetween "2.101.0" latestVersion version) [ "${cxxTestDir}/test23135.d" ]
          ++ (
            if versionBetween "2.092.1" "2.098.1" version then
              if versionBetween "2.092.1" "2.097.2" version then
                [
                  "${dmdTestDir}/runnable/test15779.d"
                  "${dmdTestDir}/runnable/test17868.d"
                  "${dmdTestDir}/runnable/test17868b.d"
                ]
              else
                [
                  "${dmdTestDir}/runnable/test17868.d"
                  "${dmdTestDir}/runnable/test17868b.d"
                ]
            else if versionAtLeast version "2.100.0" then
              if versionOlder version "2.106.0" then
                [
                  "${dmdTestDir}/runnable/objc_class.d"
                  "${dmdTestDir}/runnable/objc_self_test.d"
                ]
              else
                [
                  "${dmdTestDir}/runnable/objc_class.d"
                  "${dmdTestDir}/runnable/objc_self_test.d"
                  "${dmdTestDir}/runnable/closure.d"
                  "${dmdTestDir}/runnable/eh.d"
                ]
            else
              [ ]
          );
      in
      lib.naturalSort tests;
  };
in
mergeVersions [
  (between "2.084.0" latestVersion (version: {
    x86_64-linux = {
      build = true;
      check = true;
      skippedTests = (getInfo version).skippedTests;
    };
  }))
  (between "2.084.0" "2.096.2" (version: {
    x86_64-darwin = {
      build = true;
      check = false;
      skippedTests = (getInfo version).darwinSkippedTests;
    };
  }))
  (between "2.098.0" latestVersion (version: {
    x86_64-darwin = {
      build = true;
      check = true;
      skippedTests = (getInfo version).darwinSkippedTests;
    };
  }))
  {
    "2.111.0".x86_64-darwin = {
      build = true;
      check = false;
    };
  }
]
