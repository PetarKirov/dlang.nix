{lib}: let
  inherit (lib) versionOlder versionAtLeast nameValuePair listToAttrs;

  versionBetween = after: before: version:
    ((builtins.compareVersions version after) >= 0)
    && ((builtins.compareVersions version before) < 0);

  supportedVersions =
    builtins.attrNames
    (lib.importJSON ./supported-source-versions.json);

  mergeVersions = attrs: lib.foldr lib.recursiveUpdate {} attrs;

  between = start: end: func:
    lib.pipe supportedVersions [
      (builtins.filter (version: versionBetween start end version))
      (builtins.map (version: nameValuePair version (func version)))
      listToAttrs
    ];

  getInfo = version: rec {
    hasDruntimeRepo = versionOlder version "2.101.0";

    dmdTestDir =
      if hasDruntimeRepo
      then "dmd/test"
      else "dmd/compiler/test";

    cxxTestDir =
      if lib.versionAtLeast version "2.092.0"
      then "${dmdTestDir}/runnable_cxx"
      else "${dmdTestDir}/runnable";

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

        # tests that rely on objdump whitespace
        "${dmdTestDir}/runnable/cdvecfill.sh"
        "${dmdTestDir}/compilable/cdcmp.d"
      ]
      ++ lib.optionals (versionBetween "2.089.0" "2.092.2" version) [
        "${dmdTestDir}/dshell/test6952.d"
      ];

    darwinSkippedTests = let
      tests =
        skippedTests
        ++ [
          "${cxxTestDir}/cpp11.d"
          "${cxxTestDir}/cpp_stdlib.d"
          "${cxxTestDir}/cppa.d"
        ]
        ++ (
          if versionBetween "2.092.1" "2.099.0" version
          then
            if versionBetween "2.092.1" "2.098.0" version
            then [
              "${dmdTestDir}/runnable/test15779.d"
              "${dmdTestDir}/runnable/test17868.d"
              "${dmdTestDir}/runnable/test17868b.d"
            ]
            else [
              "${dmdTestDir}/runnable/test17868.d"
              "${dmdTestDir}/runnable/test17868b.d"
            ]
          else if versionBetween "2.100.0" "2.105.4" version
          then [
            "${dmdTestDir}/runnable/objc_class.d"
            "${dmdTestDir}/runnable/objc_self_test.d"
          ]
          else if versionAtLeast "2.105.5" version
          then [
            "${dmdTestDir}/runnable/objc_class.d"
            "${dmdTestDir}/runnable/objc_self_test.d"
          ]
          else []
        );
    in
      lib.naturalSort tests;
  };
in
  mergeVersions [
    (
      between "2.092.0" "2.105.4" (version: {
        x86_64-linux = {
          build = true;
          check = true;
          skippedTests = (getInfo version).skippedTests;
        };
      })
    )
    (
      between "2.092.0" "2.096.2" (version: {
        x86_64-darwin = {
          build = true;
          check = false;
          skippedTests = (getInfo version).darwinSkippedTests;
        };
      })
    )
    (
      between "2.098.0" "2.105.4" (version: {
        x86_64-darwin = {
          build = true;
          check = true;
          skippedTests = (getInfo version).darwinSkippedTests;
        };
      })
    )
  ]
